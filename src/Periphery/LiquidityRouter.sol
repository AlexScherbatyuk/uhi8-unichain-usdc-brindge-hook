// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

/// @notice Uniswap V4 Periphery Router - adds liquidity using the unlock callback pattern
contract LiquidityRouter is IUnlockCallback {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    IPoolManager public poolManager;

    IERC20 private usdc;
    IERC20 private usdt;
    IERC20 private link;

    struct MessageData {
        address beneficiary; // contract to call on Unichain (e.g. vault, router)
        uint8 strategy; // arbitrary calldata to forward (can be empty)
        uint256 minAmountOut; // slippage guard enforced on destination
        bytes data;
    }

    constructor(address _poolManager, address _usdc, address _link, address _usdt) {
        poolManager = IPoolManager(_poolManager);
        usdt = IERC20(_usdt);
        usdc = IERC20(_usdc);
        link = IERC20(_link);
    }

    /// @notice Entry point for adding liquidity
    function addLiquidity(PoolKey memory key, uint256 amount0, uint256 amount1) external {
        // Fund router with tokens
        IERC20(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), amount0);
        IERC20(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), amount1);

        MessageData memory messageData = MessageData({beneficiary: msg.sender, strategy: 1, minAmountOut: 0, data: ""});

        bytes memory hookData = abi.encode(msg.sender, messageData, false);
        poolManager.unlock(abi.encode(key, hookData, amount0, amount1));
    }

    /// @notice Uniswap V4 unlock callback - performs liquidity operations
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        (PoolKey memory key, bytes memory _data, uint256 amount0, uint256 amount1) =
            abi.decode(data, (PoolKey, bytes, uint256, uint256));

        PoolKey memory poolKey = key;
        // Get current pool state
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        // Calculate tick range (±600 ticks)
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-600);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(600);

        // Sync currencies to checkpoint balances
        poolManager.sync(poolKey.currency0);
        poolManager.sync(poolKey.currency1);

        // Approve tokens to PoolManager
        IERC20(Currency.unwrap(poolKey.currency0)).approve(address(poolManager), type(uint256).max);
        IERC20(Currency.unwrap(poolKey.currency1)).approve(address(poolManager), type(uint256).max);

        // Calculate required liquidity using the actual amounts passed
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, sqrtPriceAtTickLower, sqrtPriceAtTickUpper, amount0 * 5000 / 10000, amount1 * 5000 / 10000
        );

        // Add liquidity to pool
        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -600, tickUpper: 600, liquidityDelta: int256(uint256(liquidity)), salt: bytes32(0)
            }),
            _data
        );

        // Settle token deltas
        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();

        if (delta0 < 0) {
            poolKey.currency0.settle(poolManager, address(this), uint128(-delta0), false);
        } else if (delta0 > 0) {
            poolManager.take(key.currency0, address(this), uint128(delta0));
        }

        if (delta1 < 0) {
            poolKey.currency1.settle(poolManager, address(this), uint128(-delta1), false);
        } else if (delta1 > 0) {
            poolManager.take(key.currency1, address(this), uint128(delta1));
        }

        return bytes("");
    }
}
