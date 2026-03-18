// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HelperConfig} from "script/HelperConfig.sol";

contract DeployUSDCLINKPool is Script {
    // Uniswap V4 PoolManager address - needs to be set based on network
    // address internal constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;

    // Initial liquidity amounts (1:1 ratio)
    uint256 constant INITIAL_USDC = 10e6; // 10 USDC (6 decimals)
    uint256 constant INITIAL_LINK = 10e18; // 10 LINK (18 decimals)

    // Fee tier for the pool (0.30%)
    uint24 constant FEE = 3000;

    // Tick spacing
    int24 constant TICK_SPACING = 60;

    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    IERC20 usdc;
    IERC20 link;
    IPoolManager poolManager;

    function run() external {
        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();
        deploy(config.poolManager);
    }

    function deploy(address _poolManager) public returns (PoolKey memory key) {
        if (address(helpConfig) == address(0)) {
            helpConfig = new HelperConfig();
            config = helpConfig.getConfig();
        }

        usdc = IERC20(config.usdc);
        link = IERC20(config.linkTokens[0]);
        poolManager = IPoolManager(_poolManager);

        vm.startBroadcast();

        // Create the pool key with proper currency ordering
        key = _createPoolKey();

        // Initialize the pool with 1:1 price (sqrtPriceX96 = 2^96)
        uint160 sqrtPriceX96 = uint160(2 ** 96);
        poolManager.initialize(key, sqrtPriceX96);

        console.log("Pool initialized with key:");
        console.log("Currency0:", Currency.unwrap(key.currency0));
        console.log("Currency1:", Currency.unwrap(key.currency1));
        console.log("Fee:", key.fee);

        // Add initial liquidity
        // _addLiquidity(key); do not add initial liqudity at deploy

        vm.stopBroadcast();

        console.log("USDC/LINK pool deployed successfully!");
        console.log("Pool Manager:", address(poolManager));
        console.log("USDC Address:", config.usdc);
        console.log("LINK Address:", config.linkTokens[0]);
    }

    /**
     * @dev Creates a PoolKey with proper currency ordering
     * @return PoolKey with currency0 < currency1
     */
    function _createPoolKey() internal view returns (PoolKey memory) {
        Currency currency0;
        Currency currency1;

        // Ensure proper ordering (currency0 < currency1)
        if (config.usdc < config.linkTokens[0]) {
            currency0 = Currency.wrap(config.usdc);
            currency1 = Currency.wrap(config.linkTokens[0]);
        } else {
            currency0 = Currency.wrap(config.linkTokens[0]);
            currency1 = Currency.wrap(config.usdc);
        }

        return PoolKey({
            currency0: currency0, currency1: currency1, fee: FEE, tickSpacing: TICK_SPACING, hooks: IHooks(address(0))
        });
    }

    /**
     * @dev Adds initial liquidity to the pool
     * @param key The pool key
     */
    function addLiquidity(PoolKey memory key) public {
        // Calculate liquidity for the given amounts
        // Using a wide range around the current tick (±600 ticks = ±60 * 10)
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-600);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(600);
        uint160 sqrtPriceX96 = uint160(2 ** 96); // 1:1 price

        // Determine which token is currency0 and which is currency1
        bool usdcIsCurrency0 = Currency.unwrap(key.currency0) == config.usdc;

        uint128 liquidity;
        if (usdcIsCurrency0) {
            // USDC is currency0, LINK is currency1
            liquidity =
                LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtPriceAtTickUpper, uint256(INITIAL_USDC));
        } else {
            // LINK is currency0, USDC is currency1
            liquidity =
                LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtPriceAtTickUpper, uint256(INITIAL_LINK));
        }

        // Modify liquidity through pool manager
        poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -600, tickUpper: 600, liquidityDelta: int256(uint256(liquidity)), salt: bytes32(0)
            }),
            bytes("")
        );

        console.log("Liquidity added successfully!");
        console.log("Liquidity amount:", uint256(liquidity));
    }
}
