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
import {LiquidityRouter} from "src/periphery/LiquidityRouter.sol";

contract AddLiqudityToUSDCLINKPool is Script {
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    function run() public {
        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();
        IPoolManager poolManager = IPoolManager(config.poolManager);

        // Initialize pool if needed
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(config.usdc),
            currency1: Currency.wrap(config.linkTokens[0]),
            fee: 300,
            tickSpacing: 60,
            hooks: IHooks(config.usdcLinkPoolHook)
        });

        // Deploy router and add liquidity
        vm.startBroadcast();

        // Initialize pool if needed
        _initializePoolIfNeeded(poolManager, key);

        LiquidityRouter router = LiquidityRouter(config.liquidityRouter);
        // LiquidityRouter router =
        //     new LiquidityRouter(address(poolManager), config.usdc, config.linkTokens[0], config.usdt);

        router.addLiquidity(key, 1e6, 1e18);
        vm.stopBroadcast();

        console.log("Liquidity added successfully!");
        checkPoolBalance(poolManager, key);
    }

    function _initializePoolIfNeeded(IPoolManager poolManager, PoolKey memory key) internal {
        PoolId poolId = PoolIdLibrary.toId(key);
        (uint160 sqrtPriceX96, int24 tick,,) = poolManager.getSlot0(poolId);

        if (sqrtPriceX96 == 0) {
            uint160 initialPrice = uint160(2 ** 96);
            poolManager.initialize(key, initialPrice);
            console.log("Pool initialized with 1:1 price");
        } else {
            console.log("Pool already initialized at sqrtPriceX96:", uint256(sqrtPriceX96));
            console.log("Current tick:", int256(tick));
        }
    }

    /// @notice Check pool liquidity and token balances
    function checkPoolBalance(IPoolManager poolManager, PoolKey memory key) internal view {
        PoolId poolId = PoolIdLibrary.toId(key);

        // Get pool state
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 hookFee) = poolManager.getSlot0(poolId);
        uint128 liquidity = poolManager.getLiquidity(poolId);

        // Get token balances in PoolManager
        uint256 balance0 = IERC20(Currency.unwrap(key.currency0)).balanceOf(address(poolManager));
        uint256 balance1 = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(poolManager));

        console.log("=== Pool Balance Info ===");
        console.log("Pool ID:", uint256(PoolId.unwrap(poolId)));
        console.log("Total Liquidity:", uint256(liquidity));
        console.log("Current Tick:", int256(tick));
        console.log("SqrtPrice (X96):", uint256(sqrtPriceX96));
        console.log("Currency0 Balance in PoolManager:", balance0);
        console.log("Currency1 Balance in PoolManager:", balance1);
        console.log("Protocol Fee:", uint256(protocolFee));
        console.log("Hook Fee:", uint256(hookFee));
    }
}
