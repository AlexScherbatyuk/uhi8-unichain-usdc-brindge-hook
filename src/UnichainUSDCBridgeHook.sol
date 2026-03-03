// SPDX License-Identifier: MIT
pragma solidity ^0.8.26;

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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UnichainUSDCBridgeHook is BaseHook {
    using CurrencyLibrary for Currency;
    using LPFeeLibrary for uint24;
    using SafeERC20 for IERC20;

    struct MessageData {
        address recipient; // fallback receiver if calldata is empty
        address target; // contract to call on Unichain (e.g. vault, router)
        bytes callData; // arbitrary calldata to forward (can be empty)
        uint256 minAmountOut; // slippage guard enforced on destination
    }

    address public immutable usdc;
    uint24 public constant BASE_FEE = 1000;

    error NotUSDCOutput();
    error SlippageExceeded(uint256 actual, uint256 minimum);
    error InvalidDelta();
    error InsufficientRelayFee(uint256 required, uint256 provided);
    error MustUseDynamicFee();

    event BridgeInitiated(uint64 indexed wormholeSequence, address indexed swapper, uint256 usdcAmount, address target);
    event BeforeSwapHook();

    constructor(IPoolManager _manager, address _usdc) BaseHook(_manager) {
        usdc = _usdc;
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
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeInitialize(address, PoolKey calldata key, uint160) internal pure override returns (bytes4) {
        // `.isDynamicFee()` function comes from using
        // the `LPFeeLibrary` for `uint24`
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Validate input is USDC, otherwise ignore and continue as normal swap
        if (Currency.unwrap(key.currency0) != usdc && Currency.unwrap(key.currency1) != usdc) {
            return
                (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG);
        }

        // Validate zeroForOne is correct for USDC position, otherwise ignore and continue as normal swap
        if (params.zeroForOne) {
            if (Currency.unwrap(key.currency0) != usdc) {
                return (
                    this.beforeSwap.selector,
                    BeforeSwapDeltaLibrary.ZERO_DELTA,
                    BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG
                );
            }
        } else {
            if (Currency.unwrap(key.currency1) != usdc) {
                return (
                    this.beforeSwap.selector,
                    BeforeSwapDeltaLibrary.ZERO_DELTA,
                    BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG
                );
            }
        }

        // Custom logic for handling swaps involving USDC goes here

        bool deductFee = true; // deduct from swap amount to cover fees

        // Use amountSpecified to determin how to applay fees (hook fee, bridge fee, etc)
        // For example, if amountSpecified is negative (exact in), we can deduct fees from the swap amount.
        // If amountSpecified is positive (exact out), we need to pull additional amount from the user to cover fees.
        if (params.amountSpecified > 0) {
            deductFee = false; // pull additional amount from user to cover fees
        }

        // Verify hookData is not empty, otherwise ignore and continue as normal swap
        if (hookData.length == 0) {
            return
                (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG);
        }

        uint256 amountSpecified = deductFee ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        int128 absInputAmount;
        int128 absOutputAmount;
        BeforeSwapDelta beforeSwapDelta;

        if (deductFee) {
            absInputAmount = int128(-params.amountSpecified);
            absOutputAmount = absInputAmount;

            beforeSwapDelta = toBeforeSwapDelta(
                absInputAmount, // abs(params.amountSpecified) of input token owed from uniswap to hook
                -absOutputAmount // -abs(params.amountSpecified) i.e. params.amountSpecified of output token owed from hook to uniswap
            );
        } else {
            absOutputAmount = int128(params.amountSpecified);
            absInputAmount = absOutputAmount; // exactly 1:1

            beforeSwapDelta = toBeforeSwapDelta(
                -absInputAmount, // -abs(params.amountSpecified) of output token owed from hook to uniswap
                absOutputAmount // abs(params.amountSpecified) of input token owed from uniswap to hook
            );
        }

        // Bridge logic goes here
        _bridge(amountSpecified, hookData);

        return (this.beforeSwap.selector, beforeSwapDelta, 0);
    }

    function _afterSwap(
        address, // not a sender it is poolManager or router
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // 1. Validate output is USDC and decode amount from delta
        (Currency outputCurrency, uint256 usdcAmount) = _resolveOutput(key, params, delta);

        // Validate output is USDC, otherwise ignore and continue as normal swap
        if (Currency.unwrap(outputCurrency) != usdc) {
            return (this.afterSwap.selector, 0);
        }

        // 2. Check hookData is not empty, otherwise ignore and continue as normal swap
        if (hookData.length == 0) {
            return (this.afterSwap.selector, 0);
        }

        // 3. Decode intent from hookData
        //MessageData memory intent = abi.decode(hookData, (MessageData));

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

    function _bridge(uint256 usdcAmount, bytes memory bridgeData) internal {
        //uint24 hookFee = getFee();
    }
    receive() external payable {}
}
