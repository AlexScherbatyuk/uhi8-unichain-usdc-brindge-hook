// SPDX License-Identifier: MIT
pragma solidity ^0.8.26;

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

contract UnichainUSDCBridgeHook is BaseHook {
    using CurrencyLibrary for Currency;
    using LPFeeLibrary for uint24;
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    struct MessageData {
        address recipient; // fallback receiver if calldata is empty
        address target; // contract to call on Unichain (e.g. vault, router)
        bytes callData; // arbitrary calldata to forward (can be empty)
        uint256 minAmountOut; // slippage guard enforced on destination
    }

    IERC20 public immutable usdc;
    IERC20 public immutable usdt; // TODO: only for tests purpoces, delete

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

    constructor(IPoolManager _manager, address _usdc, address _usdt) BaseHook(_manager) {
        usdc = IERC20(_usdc);
        usdt = IERC20(_usdt);
    }

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

    function _beforeInitialize(address, PoolKey calldata key, uint160)
        internal
        override
        onlyPoolManager
        returns (bytes4)
    {
        // Verify the pool is initializing with dynamicFee enabled
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Validate USDC is among the currencies, otherwise ignore and continue as normal swap
        if (Currency.unwrap(key.currency0) != address(usdc) && Currency.unwrap(key.currency1) != address(usdc)) {
            return
                (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG);
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
            if (Currency.unwrap(key.currency0) != address(usdc)) {
                emit SkipBridgeConditionsNotMet();
                return (
                    this.beforeSwap.selector,
                    BeforeSwapDeltaLibrary.ZERO_DELTA,
                    BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG
                );
            }
        } else {
            // Validates that currency1 is usdc, otherwise apply swap fee and skip the logic
            if (Currency.unwrap(key.currency1) != address(usdc) || params.amountSpecified > 0) {
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
        (address user, bool deductFee) = abi.decode(hookData, (address, bool));

        // convert int amount that can be positive or negative to uint, always positive
        uint256 amount = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        // perform settle and take operations in regard to the swap direction
        if (params.zeroForOne) {
            poolManager.take(key.currency0, address(this), uint128(amountIn > 0 ? amountIn : amount));
            if (params.amountSpecified > 0) {
                poolKey.currency0.settle(poolManager, address(user), uint128(amountIn > 0 ? amountIn : amount), false);
            }
        } else {
            poolManager.take(key.currency1, address(this), uint128(amount));
            if (params.amountSpecified > 0) {
                poolKey.currency1.settle(poolManager, address(user), uint128(amountIn > 0 ? amountIn : amount), false);
            }
        }

        // if above logic is correct this condition never evaluates to true, so this revert is never reached.
        if (usdc.balanceOf(address(this)) == 0) {
            revert InefficientUSDCBalance();
        }

        // main bridge logic

        _bridge(amount, hookData);

        // no swap fee on this one, only bridge fee
        // TODO: aplay fee only for swappers that are not LP
        return (this.beforeSwap.selector, beforeSwapDelta, 0);
    }

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
            if (delta.amount1() <= 0 || Currency.unwrap(key.currency1) != address(usdc) || params.amountSpecified > 0) {
                emit SkipBridgeConditionsNotMet();
                return (this.afterSwap.selector, 0); // skip bridge logic perform regular swap
            }
            outputCurrency = key.currency1;
            usdcAmount = delta.amount1();
        } else {
            if (delta.amount0() <= 0 || Currency.unwrap(key.currency0) != address(usdc) || params.amountSpecified > 0) {
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
        // (address user,) = abi.decode(hookData, (address, bool));
        poolManager.take(outputCurrency, address(this), uint256(int256(usdcAmount)));

        return (this.afterSwap.selector, usdcAmount);
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        if (Currency.unwrap(key.currency0) != address(usdc) && Currency.unwrap(key.currency1) != address(usdc)) {
            return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
        }
        if (hookData.length == 0) {
            emit Debug(1);
            return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
        }
        emit Debug(2);
        emit Debug(delta.amount0());
        emit Debug(delta.amount1());
        if (Currency.unwrap(key.currency0) == address(usdc)) {
            emit Debug(3);
            //uint256 reserve = uint256(-int256(delta.amount0())) * RESERVE_BPS / 10000;
            uint256 reserve = uint256(-int256(delta.amount0()));
            key.currency0.take(poolManager, address(this), reserve, false); // hook delta = -reserve
            return (this.afterAddLiquidity.selector, toBalanceDelta(int128(int256(reserve)), 0)); // hookDelta = +reserve → hook net = 0, caller pays extra
        } else {
            emit Debug(4);
            //uint256 reserve = uint256(-int256(delta.amount1())) * RESERVE_BPS / 10000;
            uint256 reserve = uint256(-int256(delta.amount0()));
            key.currency1.take(poolManager, address(this), reserve, false); // hook delta = -reserve
            return (this.afterAddLiquidity.selector, toBalanceDelta(0, int128(int256(reserve))));
        }
    }
    // ─────────────────────────────────────────────────────────────
    //  Helpers
    // ─────────────────────────────────────────────────────────────

    function _calculateUnspecified(PoolKey calldata key, SwapParams calldata params)
        internal
        returns (uint256 amountIn, uint256 amountOut)
    {
        PoolId poolId = key.toId();

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        int256 amountSpecified = params.amountSpecified;

        (, uint256 amountIn, uint256 amountOut,) = SwapMath.computeSwapStep({
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

    function getFee() internal pure returns (uint24) {
        // In a real implementation, you would likely want to calculate the fee based on various factors
        // such as current market conditions, the size of the swap, etc. For simplicity, we are using a fixed fee here.
        return BASE_FEE;
    }

    function _bridge(uint256 usdcAmount, bytes memory bridgeData) internal {
        //uint24 hookFee = getFee();
    }
    receive() external payable {}
}
