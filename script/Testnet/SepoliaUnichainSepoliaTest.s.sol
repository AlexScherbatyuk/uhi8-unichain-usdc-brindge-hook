// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {UnichainUSDCBridgeHook} from "src/UnichainUSDCBridgeHook.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract SepoliaUnichainSepoliaTest is Script {
    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    function run() external {
        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();

        uint64 destinationChainId;

        for (uint64 i; i < config.destinationChainIds.length; ++i) {
            if (config.destinationChainIds[i] == block.chainid) {
                destinationChainId = i;
            }
        }

        uint256 amount = 1e6;

        vm.startBroadcast();
        UnichainUSDCBridgeHook(config.srcChainSender)
            .sendMessagePayLINK({
                _destinationChainSelector: config.destinationChainSelectors[1],
                _beneficiary: msg.sender,
                _amount: amount,
                _strategy: 1,
                _data: ""
            });
        vm.stopBroadcast();
    }
}
