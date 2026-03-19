// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SwapMath} from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {BaseHook} from "v4-hooks-public/src/base/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {USDCBridgeSender} from "./USDCBridgeSender.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IStaker} from "src/interfaces/IStaker.sol";

/**
 * @title UnichainUSDCBridgeHook
 * @author Alexander Scherbatyuk (http://x.com/AlexScherbatyuk)
 * @notice A Uniswap v4 hook that bridges USDC to the Unichain network via Chainlink CCIP.
 * @dev This hook intercepts swaps and liquidity operations involving USDC, automatically bridging
 * the USDC portion to the destination chain via CCIP. It supports bridging on input (beforeSwap),
 * output (afterSwap), and liquidity addition (afterAddLiquidity) operations. The hook enforces
 * dynamic fee mode and deducts bridge fees (LINK for CCIP + protocol fee) before sending USDC
 * to the destination chain. Swaps USDC for LINK within an unlocked PoolManager context to pay
 * for CCIP bridge fees.
 *
 * @dev Key features:
 * - Intercepts USDC swaps and bridging via hookData encoding
 * - Calculates and deducts CCIP bridge fees in LINK tokens
 * - Collects protocol fees (0.1%) donated back to the pool
 * - Supports simulation mode for testing without actual bridging
 * - Enforces minimum output amounts (slippage protection) on destination chain
 * - Requires pools to use dynamic fee mode for initialization
 */
contract UnichainUSDCBridgeHook is BaseHook, USDCBridgeSender {
    using CurrencyLibrary for Currency;
    using LPFeeLibrary for uint24;
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    struct MessageData {
        address beneficiary; // contract to call on Unichain (e.g. vault, router)
        uint8 strategy; // arbitrary calldata to forward (can be empty)
        uint256 minAmountOut; // slippage guard enforced on destination
        bytes data;
    }

    uint64 public immutable destinationChainSelector; // Unichain destination selector
    address public immutable usdcLinkPoolHook; // Pool key for the USDC/LINK pool used to buy LINK for fees

    uint24 public constant BASE_FEE = 1000; // 10%
    uint24 public constant PROTOCOL_FEE = 10; // 0.1%
    uint24 public constant DENOMINATOR = 10_000;

    error UnichainUSDCBridgeHook_NotUSDCOutput();
    error UnichainUSDCBridgeHook_SlippageExceeded(uint256 actual, uint256 minimum);
    error UnichainUSDCBridgeHook_MustUseDynamicFee();
    error UnichainUSDCBridgeHook_InefficientUSDCBalance();

    /**
     * @notice Constructor initializes the hook with the pool manager, USDC token, LINK token, CCIP router, and destination chain.
     * @param _manager The Uniswap v4 pool manager address.
     * @param _usdc The address of the USDC token contract.
     * @param _link The address of the LINK token contract.
     * @param _router The address of the CCIP router contract.
     * @param _destinationChainSelector The CCIP chain selector for the destination chain.
     */
    constructor(
        IPoolManager _manager,
        address _usdc,
        address _link,
        address _router,
        address _usdcLinkPoolHook,
        uint64 _destinationChainSelector,
        address owner
    ) BaseHook(_manager) USDCBridgeSender(_router, _link, _usdc, owner) {
        destinationChainSelector = _destinationChainSelector;
        usdcLinkPoolHook = _usdcLinkPoolHook;
    }

    /**
     * @notice Returns the hook permission flags for this hook.
     * @return Hooks.Permissions struct indicating which hook callbacks are enabled.
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: true,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @notice Hook called before a pool is initialized. Enforces that the pool uses a dynamic fee.
     * @param key The pool key of the pool being initialized.
     * @return The function selector to confirm the hook call succeeded.
     */
    function _beforeInitialize(address, PoolKey calldata key, uint160)
        internal
        view
        override
        onlyPoolManager
        returns (bytes4)
    {
        // Verify the pool is initializing with dynamicFee enabled
        if (!key.fee.isDynamicFee()) revert UnichainUSDCBridgeHook_MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    /**
     * @notice Hook called before a swap. Intercepts USDC swaps and triggers bridging when hookData is provided.
     * @dev If USDC is the input currency and hookData is non-empty, takes USDC from the pool and bridges it
     * to the destination chain instead of executing a normal swap.
     * @param key The pool key identifying the pool.
     * @param params The swap parameters including direction and amount.
     * @param hookData ABI-encoded (address msgSender, MessageData messageData, bool simulation).
     * @return The function selector, the BeforeSwapDelta, and the override fee.
     */
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolKey memory poolKey = key;
        // Validate USDC is among the currencies, otherwise ignore and continue as normal swap
        if (
            Currency.unwrap(poolKey.currency0) != address(i_usdcToken)
                && Currency.unwrap(poolKey.currency1) != address(i_usdcToken)
        ) {
            return (
                this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG
            );
        }

        // Bridge logic is working only if incoming currency is USDC
        // therefore if one of two conditions is not met:
        // - if zeroForOne is true the key.currency0 must be usdc
        // - if zeroForOne is false the key.currency1 must be usdc
        // otherwise, skip the internal logic.

        // BeforeSwap scenarios that can trigger bridge if hookdata is provided:
        // USDC/USDT as (currency0/currency1)
        // - zeroForOne == true,  user provides USDC (as currency0) with amountSpecified < 0 receives nothing (bridge)
        // - zeroForOne == false, user provides USDC (as currency1) with amountSpecified < 0 receives nothing (bridge)

        // Validate zeroForOne is correct for USDC position, otherwise ignore and continue as normal swap
        if (params.zeroForOne) {
            // Validates that currency0 is usdc, otherwise apply swap fee and skip the logic
            if (Currency.unwrap(poolKey.currency0) != address(i_usdcToken) || params.amountSpecified > 0) {
                return (
                    this.beforeSwap.selector,
                    BeforeSwapDeltaLibrary.ZERO_DELTA,
                    BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG
                );
            }
        } else {
            // Validates that currency1 is usdc, otherwise apply swap fee and skip the logic
            if (Currency.unwrap(poolKey.currency1) != address(i_usdcToken) || params.amountSpecified > 0) {
                return (
                    this.beforeSwap.selector,
                    BeforeSwapDeltaLibrary.ZERO_DELTA,
                    BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG
                );
            }
        }

        // Now we are sure that if it is zeroForOne == true currency0 is usdc
        // if zeroForOne == false currency1 is usdc

        // Verify hookData is not empty, otherwise ignore and continue as normal swap and apply swap fee
        if (hookData.length == 0) {
            return
                (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG);
        }

        // Custom logic for handling swaps involving USDC goes here
        // Use amountSpecified to determine how to apply fees (hook fee, bridge fee, etc)

        BeforeSwapDelta beforeSwapDelta;
        uint256 amountIn;

        if (params.amountSpecified < 0) {
            beforeSwapDelta = toBeforeSwapDelta({
                deltaSpecified: -int128(int256(params.amountSpecified)),
                deltaUnspecified: 0 // tokens to return
            });
        }
        (address msgSender, MessageData memory messageData, bool simulation) =
            abi.decode(hookData, (address, MessageData, bool));

        // convert int amount that can be positive or negative to uint, always positive
        uint256 amount = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        // perform settle and take operations in regard to the swap direction
        if (params.zeroForOne) {
            poolManager.take(poolKey.currency0, address(this), uint128(amountIn > 0 ? amountIn : amount));
            if (params.amountSpecified > 0) {
                poolKey.currency0
                    .settle(poolManager, address(msgSender), uint128(amountIn > 0 ? amountIn : amount), false);
            }
        } else {
            poolManager.take(poolKey.currency1, address(this), uint128(amount));
            if (params.amountSpecified > 0) {
                poolKey.currency1
                    .settle(poolManager, address(msgSender), uint128(amountIn > 0 ? amountIn : amount), false);
            }
        }

        // if above logic is correct this condition never evaluates to true, so this revert is never reached.
        if (i_usdcToken.balanceOf(address(this)) == 0) {
            revert UnichainUSDCBridgeHook_InefficientUSDCBalance();
        }

        // main bridge logic
        if (!simulation) {
            _bridge(poolKey, amount, msgSender, messageData);
        }

        // no swap fee on this one, only bridge fee
        return (this.beforeSwap.selector, beforeSwapDelta, 0);
    }

    /**
     * @notice Hook called after a swap. Intercepts swaps where USDC is the output currency and bridges it.
     * @dev If USDC is the output currency and hookData is non-empty, takes the USDC output and bridges it
     * to the destination chain instead of returning it to the swapper.
     * @param key The pool key identifying the pool.
     * @param params The swap parameters including direction and amount.
     * @param delta The balance delta resulting from the swap.
     * @param hookData ABI-encoded (address msgSender, MessageData messageData, bool simulation).
     * @return The function selector and the hook's delta on the output currency.
     */
    function _afterSwap(
        address, // not a sender it is poolManager or router
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override onlyPoolManager returns (bytes4, int128) {
        // Validate it is regular swap (meaning before swap internal logic was skipped)

        // AfterSwap scenarios that can trigger bridge if hookdata is provided:
        // USDT/USDC as (currency0/currency1)
        // - zeroForOne == true, user provides USDT (as currency0) with amountSpecified < 0 receives USDC as currency1
        // - zeroForOne == false, user provides USDT (as currency1) with amountSpecified < 0 receives USDC as currency1

        Currency outputCurrency;
        int128 usdcAmount;
        PoolKey memory poolKey = key;
        if (params.zeroForOne) {
            if (
                delta.amount1() <= 0 || Currency.unwrap(poolKey.currency1) != address(i_usdcToken)
                    || params.amountSpecified > 0
            ) {
                return (this.afterSwap.selector, 0); // skip bridge logic perform regular swap
            }
            outputCurrency = poolKey.currency1;
            usdcAmount = delta.amount1();
        } else {
            if (
                delta.amount0() <= 0 || Currency.unwrap(poolKey.currency0) != address(i_usdcToken)
                    || params.amountSpecified > 0
            ) {
                return (this.afterSwap.selector, 0); // skip bridge logic perform regular swap
            }
            outputCurrency = poolKey.currency0;
            usdcAmount = delta.amount0();
        }
        if (hookData.length == 0) {
            return (this.afterSwap.selector, 0); // skip bridge logic perform regular swap
        }
        uint256 amount = uint256(int256(usdcAmount));
        poolManager.take(outputCurrency, address(this), amount);

        (address msgSender, MessageData memory messageData, bool simulation) =
            abi.decode(hookData, (address, MessageData, bool));

        if (!simulation) {
            _bridge(poolKey, amount, msgSender, messageData);
        }

        return (this.afterSwap.selector, usdcAmount);
    }

    /**
     * @notice Hook called after liquidity is added. Takes the USDC portion of the added liquidity and bridges it.
     * @dev Only triggers when USDC is one of the pool currencies and hookData is non-empty.
     * @param key The pool key identifying the pool.
     * @param delta The balance delta from the liquidity addition.
     * @param hookData ABI-encoded (address msgSender, MessageData messageData, bool simulation).
     * @return The function selector and the hook's BalanceDelta adjustment.
     */
    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        PoolKey memory poolKey = key;
        if (
            Currency.unwrap(poolKey.currency0) != address(i_usdcToken)
                && Currency.unwrap(poolKey.currency1) != address(i_usdcToken)
        ) {
            return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
        }
        if (hookData.length == 0) {
            return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
        }

        BalanceDelta returnBalanceDelta;
        uint256 amount;
        if (Currency.unwrap(poolKey.currency0) == address(i_usdcToken)) {
            amount = uint256(-int256(delta.amount0()));
            poolKey.currency0.take(poolManager, address(this), amount, false); // hook delta = -reserve
            returnBalanceDelta = toBalanceDelta(int128(int256(amount)), 0); // hookDelta = +reserve → hook net = 0, caller pays extra
        } else {
            amount = uint256(-int256(delta.amount0()));
            poolKey.currency1.take(poolManager, address(this), amount, false); // hook delta = -reserve
            returnBalanceDelta = toBalanceDelta(0, int128(int256(amount)));
        }

        (address msgSender, MessageData memory messageData, bool simulation) =
            abi.decode(hookData, (address, MessageData, bool));

        if (!simulation) {
            _bridge(poolKey, amount, msgSender, messageData);
        }

        return (this.afterAddLiquidity.selector, returnBalanceDelta);
    }

    // ─────────────────────────────────────────────────────────────
    //  Helpers
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice Swaps USDC for LINK inside the already-unlocked PoolManager.
     * @dev Called from hook callbacks where the PoolManager lock is already held.
     *      Settles USDC from this contract's balance and takes LINK into this contract.
     * @param amount The exact amount of USDC to swap in.
     * @return The remaining USDC balance after the swap.
     */
    function _swapUSDCToLink(uint256 amount) internal returns (uint256) {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(i_usdcToken)),
            currency1: Currency.wrap(address(i_linkToken)),
            fee: 300,
            tickSpacing: 60,
            hooks: IHooks(usdcLinkPoolHook)
        });

        // Determine swap direction: currency0 < currency1 by address (Uniswap ordering)
        bool zeroForOne = address(i_usdcToken) < address(i_linkToken);

        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amount), // exact input
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        BalanceDelta delta = poolManager.swap(key, swapParams, "");

        if (zeroForOne) {
            // USDC is currency0: we owe USDC (delta.amount0 < 0), receive LINK (delta.amount1 > 0)
            key.currency0.settle(poolManager, address(this), amount, false);
            key.currency1.take(poolManager, address(this), uint256(int256(delta.amount1())), false);
        } else {
            // USDC is currency1: we owe USDC (delta.amount1 < 0), receive LINK (delta.amount0 > 0)
            key.currency1.settle(poolManager, address(this), amount, false);
            key.currency0.take(poolManager, address(this), uint256(int256(delta.amount0())), false);
        }

        return i_usdcToken.balanceOf(address(this));
    }

    /**
     * @notice Sends USDC to the destination chain via CCIP and donates the protocol fee to the pool.
     * @dev Calculates and deducts LINK and protocol fees, then sends the remaining USDC via CCIP.
     * @param poolKey The pool key identifying the pool for protocol fee donation.
     * @param amount The amount of USDC to bridge.
     * @param sender The address initiating the bridge (included in encoded message data for destination execution).
     * @param messageData The message data containing the target address and calldata for the destination chain.
     * @return protocolFee The protocol fee amount deducted and donated to the pool.
     */
    function _bridge(PoolKey memory poolKey, uint256 amount, address sender, MessageData memory messageData)
        internal
        returns (uint256 protocolFee)
    {
        uint256 linkFee = calculateBridgeFee(amount, messageData.beneficiary, messageData.strategy, messageData.data);

        uint256 usdcFee = _swapUSDCToLink(linkFee);

        protocolFee = amount * PROTOCOL_FEE / DENOMINATOR; // 0.01 %

        uint256 totalFee = usdcFee + protocolFee;

        if (totalFee >= amount) {
            revert UnichainUSDCBridgeHook_InefficientUSDCBalance();
        }

        uint256 finalAmount = amount - totalFee;

        if (messageData.minAmountOut > 0 && messageData.minAmountOut < finalAmount) {
            revert UnichainUSDCBridgeHook_SlippageExceeded(finalAmount, messageData.minAmountOut);
        }

        if (Currency.unwrap(poolKey.currency0) == address(i_usdcToken)) {
            poolManager.donate(poolKey, protocolFee, 0, "");
        } else {
            poolManager.donate(poolKey, 0, protocolFee, "");
        }

        sendMessagePayLINK({
            _destinationChainSelector: destinationChainSelector, // uint64
            _beneficiary: messageData.beneficiary,
            _amount: finalAmount, // uint256
            _strategy: messageData.strategy, //bytes memory
            _data: messageData.data
        });

        return protocolFee;
    }

    /**
     * @notice Calculates the CCIP bridge fee required to send USDC to the destination chain.
     * @dev Queries the CCIP router for the fee based on the message parameters and destination chain.
     * @param _amount The amount of USDC to bridge.
     * @param _beneficiary The beneficiary address for the stake/transfer on the destination chain.
     * @param _strategy The strategy for handling the transfer (EOA, STAKER, or AAVE).
     * @return fees The calculated fee in LINK tokens required for this bridge transaction.
     */
    function calculateBridgeFee(uint256 _amount, address _beneficiary, uint256 _strategy, bytes memory _data)
        public
        view
        returns (uint256 fees)
    {
        address receiver = s_receivers[destinationChainSelector];
        if (receiver == address(0)) {
            revert NoReceiverOnDestinationChain(destinationChainSelector);
        }
        if (_amount == 0) revert AmountIsZero();
        uint256 gasLimit = s_gasLimits[destinationChainSelector];
        if (gasLimit == 0) {
            revert NoGasLimitOnDestinationChain(destinationChainSelector);
        }

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(i_usdcToken), amount: _amount});
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // ABI-encoded receiver of destination receiver contract
            //data: abi.encode(_beneficiary, _strategy, amount), // Packed encoding to reduce data size for CCIP limits
            // data: _strategy == 0
            //     ? abi.encodeWithSelector(IERC20.transfer.selector, _beneficiary, amount)
            //     : abi.encodeWithSelector(IStaker.stake.selector, _beneficiary, amount),
            data: abi.encode(_beneficiary, _strategy, _amount, _data),
            //data: bytes(""),
            tokenAmounts: tokenAmounts, // The amount and type of token being transferred
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: gasLimit, // Gas limit for the callback on the destination chain
                    allowOutOfOrderExecution: true // Allows the message to be executed out of order relative to other messages
                })
            ),
            feeToken: address(i_linkToken)
        });

        fees = i_router.getFee(destinationChainSelector, evm2AnyMessage);
        return fees;
    }
}
