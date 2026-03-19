// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {UnichainUSDCBridgeHook} from "src/UnichainUSDCBridgeHook.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract SenderPostDeploy is Script {
    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    function run() external {
        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();
        deploy();
    }

    function deploy() public {
        vm.startBroadcast();
        UnichainUSDCBridgeHook(config.srcChainSender)
            .setReceiverForDestinationChain(config.destinationChainSelectors[1], config.dstChainReceiver);
        UnichainUSDCBridgeHook(config.srcChainSender)
            .setGasLimitForDestinationChain(config.destinationChainSelectors[1], 20000);
        vm.stopBroadcast();
    }
}
