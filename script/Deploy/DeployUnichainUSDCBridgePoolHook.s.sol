// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployUnichainUSDCBridgeHook} from "script/Deploy/DeployUnichainUSDCBridgeHook.s.sol";

contract DeployUnichainUSDCBridgePoolHook is Script {
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
    IHooks hook;

    function run() external {
        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();
        DeployUnichainUSDCBridgeHook hookDeployer = new DeployUnichainUSDCBridgeHook();
        address _hook = hookDeployer.deploy();
        deploy(config.poolManager, _hook);
    }

    function deploy(address _poolManager, address _hook) public returns (PoolKey memory key) {
        if (address(helpConfig) == address(0)) {
            helpConfig = new HelperConfig();
            config = helpConfig.getConfig();
        }

        usdc = IERC20(config.usdc);
        link = IERC20(config.usdt);
        poolManager = IPoolManager(_poolManager);
        hook = IHooks(_hook);

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

        vm.stopBroadcast();

        console.log("UnichainUSDCBridgePoolHook pool deployed successfully!");
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

        return
            PoolKey({
                currency0: currency0, currency1: currency1, fee: FEE, tickSpacing: TICK_SPACING, hooks: IHooks(hook)
            });
    }
}
