// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {USDCBridgeReceiver} from "src/USDCBridgeReceiver.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployUSDCBridgeReceiver is Script {
    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    function run() external {
        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();
        deploy();
    }

    function deploy() public returns (address) {
        uint64 destinationChainId;

        for (uint64 i; i < config.destinationChainIds.length; ++i) {
            if (config.destinationChainIds[i] == block.chainid) {
                destinationChainId = i;
            }
        }
        vm.startBroadcast();

        USDCBridgeReceiver receiver =
            new USDCBridgeReceiver(config.ccipRouters[destinationChainId], config.usdc, config.staker);

        vm.stopBroadcast();
        return address(receiver);
    }
}
