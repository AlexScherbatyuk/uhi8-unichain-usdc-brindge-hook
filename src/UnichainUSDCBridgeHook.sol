// SPDX License-Identifier: MIT
pragma solidity 0.8.26;

import {SwapMath} from "@uniswap/v4-core/src/libraries/SwapMath.sol";
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

contract UnichainUSDCBridgeHook is BaseHook, USDCBridgeSender {
    using CurrencyLibrary for Currency;
    using LPFeeLibrary for uint24;
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    struct MessageData {
        address target; // contract to call on Unichain (e.g. vault, router)
        bytes callData; // arbitrary calldata to forward (can be empty)
        uint256 minAmountOut; // slippage guard enforced on destination
    }

    uint64 public immutable destinationChainSelector;

    uint24 public constant BASE_FEE = 1000;
    uint24 public constant RESERVE_BPS = 6000;

    error NotUSDCOutput();
    error SlippageExceeded(uint256 actual, uint256 minimum);
    error InvalidDelta();
    error InsufficientRelayFee(uint256 required, uint256 provided);
    error MustUseDynamicFee();
    error InefficientUSDCBalance();

    // event BridgeInitiated(uint64 indexed wormholeSequence, address indexed swapper, uint256 usdcAmount, address target);
    // event BeforeSwapHook();
    // event BeforeSwapDeltaDetails(int128, int128);
    // event ComputeSwapStep(uint256, uint256);
    // event CurrencyTokens(address, address);
    // event ZeroForOne(bool);
    // event DebugEvent(uint256);
    event Debug(int256);
    event SkipBridgeConditionsZeroHookData();
    event SkipBridgeConditionsNotMet();
    event BridgeSimulation();

    /**
     * @notice Constructor initializes the hook with the pool manager, USDC token, LINK token, CCIP router, and destination chain.
     * @param _manager The Uniswap v4 pool manager address.
     * @param _usdc The address of the USDC token contract.
     * @param _link The address of the LINK token contract.
     * @param _router The address of the CCIP router contract.
     * @param _destinationChainSelector The CCIP chain selector for the destination chain.
     */
    constructor(IPoolManager _manager, address _usdc, address _link, address _router, uint64 _destinationChainSelector)
        BaseHook(_manager)
        USDCBridgeSender(_router, _link, _usdc)
    {
        destinationChainSelector = _destinationChainSelector;
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
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
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
        // Validate USDC is among the currencies, otherwise ignore and continue as normal swap
        if (
            Currency.unwrap(key.currency0) != address(i_usdcToken)
                && Currency.unwrap(key.currency1) != address(i_usdcToken)
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
            if (Currency.unwrap(key.currency0) != address(i_usdcToken)) {
                emit SkipBridgeConditionsNotMet();
                return (
                    this.beforeSwap.selector,
                    BeforeSwapDeltaLibrary.ZERO_DELTA,
                    BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG
                );
            }
        } else {
            // Validates that currency1 is usdc, otherwise apply swap fee and skip the logic
            if (Currency.unwrap(key.currency1) != address(i_usdcToken) || params.amountSpecified > 0) {
                emit SkipBridgeConditionsNotMet();
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
            emit SkipBridgeConditionsZeroHookData();
            return
                (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG);
        }

        // Custom logic for handling swaps involving USDC goes here
        // Use amountSpecified to determine how to apply fees (hook fee, bridge fee, etc)

        BeforeSwapDelta beforeSwapDelta;
        uint256 amountIn;
        uint256 amountOut;
        PoolKey memory poolKey = key;

        if (params.amountSpecified < 0) {
            beforeSwapDelta = toBeforeSwapDelta({
                deltaSpecified: -int128(int256(params.amountSpecified)),
                deltaUnspecified: 0 // tokens to return
            });
        } else {
            (amountIn, amountOut) = _calculateUnspecified(key, params);
            beforeSwapDelta = toBeforeSwapDelta({
                deltaSpecified: -int128(int256(params.amountSpecified)),
                deltaUnspecified: -int128(int256(amountIn)) // tokens to return
            });
        }
        // return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG);

        // // decode hookData
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
            revert InefficientUSDCBalance();
        }

        // main bridge logic
        if (!simulation) {
            _bridge(amount, msgSender, messageData);
        } else {
            emit BridgeSimulation();
        }

        // no swap fee on this one, only bridge fee
        // TODO: aplay fee only for swappers that are not LP
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
        // Validate it is regular swap (menaing before swap internal logick was skipped)

        // AfterSwap scenarios that can trigger bridge if hookdata is provided:
        // USDT/USDC as (currency0/currency1)
        // - zeroForOne == true, user provides USDT (as currency0) with amountSpecified < 0 receives USDC as currency1
        // - zeroForOne == false, user provides USDT (as currency1) with amountSpecified < 0 receives USDC as currency1

        Currency outputCurrency;
        int128 usdcAmount;
        if (params.zeroForOne) {
            if (
                delta.amount1() <= 0 || Currency.unwrap(key.currency1) != address(i_usdcToken)
                    || params.amountSpecified > 0
            ) {
                emit SkipBridgeConditionsNotMet();
                return (this.afterSwap.selector, 0); // skip bridge logic perform regular swap
            }
            outputCurrency = key.currency1;
            usdcAmount = delta.amount1();
        } else {
            if (
                delta.amount0() <= 0 || Currency.unwrap(key.currency0) != address(i_usdcToken)
                    || params.amountSpecified > 0
            ) {
                emit SkipBridgeConditionsNotMet();
                return (this.afterSwap.selector, 0); // skip bridge logic perform regular swap
            }
            outputCurrency = key.currency0;
            usdcAmount = delta.amount0();
        }
        if (hookData.length == 0) {
            emit SkipBridgeConditionsZeroHookData();
            return (this.afterSwap.selector, 0); // skip bridge logic perform regular swap
        }
        uint256 amount = uint256(int256(usdcAmount));
        poolManager.take(outputCurrency, address(this), amount);

        (address msgSender, MessageData memory messageData, bool simulation) =
            abi.decode(hookData, (address, MessageData, bool));

        if (!simulation) {
            _bridge(amount, msgSender, messageData);
        } else {
            emit BridgeSimulation();
        }

        return (this.afterSwap.selector, usdcAmount);
    }

    /**
     * @notice Hook called after liquidity is added. Takes the USDC portion of the added liquidity and bridges it.
     * @dev Only triggers when USDC is one of the pool currencies and hookData is non-empty.
     * @param sender The address that added liquidity.
     * @param key The pool key identifying the pool.
     * @param params The liquidity modification parameters.
     * @param delta The balance delta from the liquidity addition.
     * @param feesAccrued Fees accrued during the liquidity operation.
     * @param hookData ABI-encoded (address msgSender, MessageData messageData, bool simulation).
     * @return The function selector and the hook's BalanceDelta adjustment.
     */
    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        if (
            Currency.unwrap(key.currency0) != address(i_usdcToken)
                && Currency.unwrap(key.currency1) != address(i_usdcToken)
        ) {
            return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
        }
        if (hookData.length == 0) {
            return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
        }

        BalanceDelta returnBalanceDelta;
        uint256 amount;
        if (Currency.unwrap(key.currency0) == address(i_usdcToken)) {
            //uint256 reserve = uint256(-int256(delta.amount0())) * RESERVE_BPS / 10000;
            amount = uint256(-int256(delta.amount0()));
            key.currency0.take(poolManager, address(this), amount, false); // hook delta = -reserve
            returnBalanceDelta = toBalanceDelta(int128(int256(amount)), 0); // hookDelta = +reserve → hook net = 0, caller pays extra
        } else {
            //uint256 reserve = uint256(-int256(delta.amount1())) * RESERVE_BPS / 10000;
            amount = uint256(-int256(delta.amount0()));
            key.currency1.take(poolManager, address(this), amount, false); // hook delta = -reserve
            returnBalanceDelta = toBalanceDelta(0, int128(int256(amount)));
        }

        (address msgSender, MessageData memory messageData, bool simulation) =
            abi.decode(hookData, (address, MessageData, bool));

        if (!simulation) {
            _bridge(amount, msgSender, messageData);
        } else {
            emit BridgeSimulation();
        }

        return (this.afterAddLiquidity.selector, returnBalanceDelta);
    }

    // ─────────────────────────────────────────────────────────────
    //  Helpers
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice Calculates the input and output amounts for an exact-output swap using the current pool price.
     * @param key The pool key identifying the pool.
     * @param params The swap parameters.
     * @return amountIn The required input amount.
     * @return amountOut The expected output amount.
     */
    function _calculateUnspecified(PoolKey calldata key, SwapParams calldata params)
        internal
        view
        returns (uint256 amountIn, uint256 amountOut)
    {
        PoolId poolId = key.toId();

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        int256 amountSpecified = params.amountSpecified;

        (, amountIn, amountOut,) = SwapMath.computeSwapStep({
            sqrtPriceCurrentX96: sqrtPriceX96,
            sqrtPriceTargetX96: params.sqrtPriceLimitX96,
            liquidity: poolManager.getLiquidity(poolId),
            amountRemaining: amountSpecified < 0
                ? int256(-amountSpecified)  // exact-in: positive remaining
                : int256(amountSpecified), // exact-out: positive remaining
            feePips: 0
        });

        return (amountIn, amountOut);
    }

    /**
     * @notice Returns the base swap fee applied to non-bridge swaps.
     * @return The fee in pips (BASE_FEE).
     */
    function getFee() internal pure returns (uint24) {
        // In a real implementation, you would likely want to calculate the fee based on various factors
        // such as current market conditions, the size of the swap, etc. For simplicity, we are using a fixed fee here.
        return BASE_FEE;
    }

    /**
     * @notice Sends USDC to the destination chain via CCIP.
     * @param amount The amount of USDC to bridge.
     * @param sender The address initiating the bridge (unused, reserved for future fee logic).
     * @param messageData The message data containing the target address and calldata for the destination chain.
     */
    function _bridge(uint256 amount, address sender, MessageData memory messageData) internal {
        //uint24 hookFee = getFee();

        bytes32 messageId = sendMessagePayLINK({
            _destinationChainSelector: destinationChainSelector, // uint64
            _beneficiary: messageData.target, // address
            _amount: amount, // uint256
            _data: messageData.callData //bytes memory
        });
    }
}
