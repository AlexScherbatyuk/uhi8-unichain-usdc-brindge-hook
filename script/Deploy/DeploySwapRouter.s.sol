// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {SwapRouter} from "src/Periphery/SwapRouter.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeploySwapRouter is Script {
    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    function run() external {
        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();
        deploy(config.poolManager);
    }

    function deploy(address poolManager) public returns (address) {
        vm.startBroadcast();
        SwapRouter router = new SwapRouter(poolManager);

        vm.stopBroadcast();
        return address(router);
    }
}
