// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

/// @notice Uniswap V4 Periphery Swap Router - swaps tokens using the unlock callback pattern
contract SwapRouter is IUnlockCallback {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    IPoolManager public poolManager;

    struct SwapData {
        address recipient;
        uint256 minAmountOut;
        bytes hookData;
    }

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    /// @notice Entry point for swapping tokens
    /// @param key The pool key for the swap
    /// @param amountIn The amount of input tokens
    /// @param zeroForOne True if swapping token0 for token1
    /// @param minAmountOut Minimum amount of output tokens (slippage protection)
    function swap(PoolKey memory key, int128 amountIn, bool zeroForOne, uint256 minAmountOut, bytes memory hookData)
        external
    {
        // Transfer input tokens to router with buffer for fees (2%)
        Currency inputCurrency = zeroForOne ? key.currency0 : key.currency1;
        //uint256 amountWithBuffer = amountIn + (amountIn * 5 / 100);

        IERC20(Currency.unwrap(inputCurrency))
            .transferFrom(
                msg.sender, address(this), amountIn >= 0 ? uint256(int256(amountIn)) : uint256(int256(-amountIn))
            );

        SwapData memory swapData = SwapData({recipient: msg.sender, minAmountOut: minAmountOut, hookData: hookData});

        bytes memory encodedData = abi.encode(key, amountIn, zeroForOne, swapData);
        poolManager.unlock(encodedData);
    }

    /// @notice Uniswap V4 unlock callback - performs swap operations
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        (PoolKey memory key, uint256 amountIn, bool zeroForOne, SwapData memory swapData) =
            abi.decode(data, (PoolKey, uint256, bool, SwapData));

        // Approve input currency to PoolManager
        Currency inputCurrency = zeroForOne ? key.currency0 : key.currency1;
        IERC20(Currency.unwrap(inputCurrency)).approve(address(poolManager), type(uint256).max);

        // Execute the swap
        // Set price limits to allow maximum price movement in either direction
        //uint160 sqrtPriceLimitX96 = zeroForOne ? type(uint160).max : 1;
        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;

        BalanceDelta delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne, amountSpecified: int256(amountIn), sqrtPriceLimitX96: sqrtPriceLimitX96
            }),
            swapData.hookData
        );

        // Settle deltas
        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();

        if (delta0 < 0) {
            key.currency0.settle(poolManager, address(this), uint128(-delta0), false);
        } else if (delta0 > 0) {
            poolManager.take(key.currency0, swapData.recipient, uint128(delta0));
        }

        if (delta1 < 0) {
            key.currency1.settle(poolManager, address(this), uint128(-delta1), false);
        } else if (delta1 > 0) {
            poolManager.take(key.currency1, swapData.recipient, uint128(delta1));
        }

        // Refund any excess input tokens to the user
        uint256 routerBalance = IERC20(Currency.unwrap(inputCurrency)).balanceOf(address(this));
        if (routerBalance > 0) {
            IERC20(Currency.unwrap(inputCurrency)).transfer(swapData.recipient, routerBalance);
        }

        return bytes("");
    }
}
