// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {LiquidityRouter} from "src/Periphery/LiquidityRouter.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployLiquidityRouter is Script {
    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    function run() external {
        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();
        deploy(config.poolManager);
    }

    function deploy(address poolManager) public returns (address) {
        vm.startBroadcast();
        LiquidityRouter router = new LiquidityRouter(poolManager, config.usdc, config.linkTokens[0], config.usdt);

        vm.stopBroadcast();
        return address(router);
    }
}
