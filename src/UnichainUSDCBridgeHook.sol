// SPDX License-Identifier: MIT
pragma solidity ^0.8.26;

import {SwapMath} from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {BaseHook} from "v4-hooks-public/src/base/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
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

    struct MessageData {
        address recipient; // fallback receiver if calldata is empty
        address target; // contract to call on Unichain (e.g. vault, router)
        bytes callData; // arbitrary calldata to forward (can be empty)
        uint256 minAmountOut; // slippage guard enforced on destination
    }

    IERC20 public immutable usdc;
    IERC20 public immutable uusdc;

    uint24 public constant BASE_FEE = 1000;

    error NotUSDCOutput();
    error SlippageExceeded(uint256 actual, uint256 minimum);
    error InvalidDelta();
    error InsufficientRelayFee(uint256 required, uint256 provided);
    error MustUseDynamicFee();
    error InefficientUSDCBalance();

    event BridgeInitiated(uint64 indexed wormholeSequence, address indexed swapper, uint256 usdcAmount, address target);
    event BeforeSwapHook();
    event BeforeSwapDeltaDetails(int128, int128);
    event ComputeSwapStep(uint256, uint256);
    event CurrencyTokens(address, address);
    event ZeroForOne(bool);
    event DebugEvent(uint256);

    constructor(IPoolManager _manager, address _usdc, address _uusdc) BaseHook(_manager) {
        usdc = IERC20(_usdc);
        uusdc = IERC20(_uusdc);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeInitialize(address, PoolKey calldata key, uint160) internal pure override returns (bytes4) {
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

        // Validate zeroForOne is correct for USDC position, otherwise ignore and continue as normal swap
        if (params.zeroForOne) {
            // Validates that currency0 is usdc, otherwise apply swap fee and skip the logic
            if (Currency.unwrap(key.currency0) != address(usdc)) {
                return (
                    this.beforeSwap.selector,
                    BeforeSwapDeltaLibrary.ZERO_DELTA,
                    BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG
                );
            }
        } else {
            // Validates that currency1 is usdc, otherwise apply swap fee and skip the logic
            if (Currency.unwrap(key.currency1) != address(usdc)) {
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
        // For example, if amountSpecified is negative (exact in), we can deduct fees from the swap amount.
        // If amountSpecified is positive (exact out), we need to pull additional amount from the user to cover fees.

        BeforeSwapDelta beforeSwapDelta;

        // calculating beforeSwapDelta to eat the swap and prevent poolManager from performing the swap
        if (params.amountSpecified < 0) {
            beforeSwapDelta = toBeforeSwapDelta({
                deltaSpecified: int128(-int256(params.amountSpecified)),
                deltaUnspecified: int128(int256(params.amountSpecified))
            });
        } else {
            beforeSwapDelta = toBeforeSwapDelta({
                deltaSpecified: int128(-int256(params.amountSpecified)),
                deltaUnspecified: int128(int256(params.amountSpecified))
            });
        }
        // decode hookData
        address user = abi.decode(hookData, (address));

        // convert int amount that can be positive or negative to uint, always positive
        uint256 amount = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        // perform settle and take operations in regard to the swap direction
        if (params.zeroForOne) {
            uusdc.transferFrom(user, address(this), amount);
            key.currency1.settle(poolManager, address(this), uint128(amount), false);
            poolManager.take(key.currency0, address(this), uint128(amount));
        } else {
            uusdc.transferFrom(user, address(this), amount);
            key.currency0.settle(poolManager, address(this), uint128(amount), false);
            poolManager.take(key.currency1, address(this), uint128(amount));
        }

        // if above logic is correct this condition never evaluates to true, so this revert is never reached.
        if (usdc.balanceOf(address(this)) == 0) {
            revert InefficientUSDCBalance();
        }

        // main bridge logic
        _bridge(amount, hookData, true);

        // no swap fee on this one, only bridge fee
        return (this.beforeSwap.selector, beforeSwapDelta, 0);
    }

    function _afterSwap(
        address, // not a sender it is poolManager or router
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override onlyPoolManager returns (bytes4, int128) {
        // // 1. Validate output is USDC and decode amount from delta
        // (Currency outputCurrency, uint256 usdcAmount) = _resolveOutput(key, params, delta);

        // // Validate output is USDC, otherwise ignore and continue as normal swap
        // if (Currency.unwrap(outputCurrency) != usdc) {
        //     return (this.afterSwap.selector, 0);
        // }

        // // 2. Check hookData is not empty, otherwise ignore and continue as normal swap
        // if (hookData.length == 0) {
        //     return (this.afterSwap.selector, 0);
        // }

        // // Bridge logic goes here
        // _bridge(uint256(params.amountSpecified), hookData, true);

        return (this.afterSwap.selector, 0);
    }

    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal pure override returns (bytes4) {
        return (this.beforeAddLiquidity.selector);
    }

    // ─────────────────────────────────────────────────────────────
    //  Helpers
    // ─────────────────────────────────────────────────────────────

    function _resolveOutput(PoolKey calldata key, SwapParams calldata params, BalanceDelta delta)
        internal
        pure
        returns (Currency currency, uint256 amount)
    {
        if (params.zeroForOne) {
            int128 raw = delta.amount1();
            if (raw <= 0) revert InvalidDelta();
            return (key.currency1, uint256(int256(raw)));
        } else {
            int128 raw = delta.amount0();
            if (raw <= 0) revert InvalidDelta();
            return (key.currency0, uint256(int256(raw)));
        }
    }

    function getFee() internal view returns (uint24) {
        // In a real implementation, you would likely want to calculate the fee based on various factors
        // such as current market conditions, the size of the swap, etc. For simplicity, we are using a fixed fee here.
        return BASE_FEE;
    }

    function _bridge(uint256 usdcAmount, bytes memory bridgeData, bool deductFee) internal {
        //uint24 hookFee = getFee();
    }
    receive() external payable {}
}
