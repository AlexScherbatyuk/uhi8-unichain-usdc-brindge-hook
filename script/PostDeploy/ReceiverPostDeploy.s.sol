// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {USDCBridgeReceiver} from "src/USDCBridgeReceiver.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract ReceiverPostDeploy is Script {
    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    function run() external {
        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();
        deploy();
    }

    function deploy() public {
        vm.startBroadcast();
        USDCBridgeReceiver(config.dstChainReceiver)
            .setSenderForSourceChain(config.destinationChainSelectors[0], config.srcChainSender);
        vm.stopBroadcast();
    }
}
