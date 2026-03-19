// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Staker} from "src/Periphery/Staker.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployStaker is Script {
    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    function run() external {
        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();
        deploy();
    }

    function deploy() public returns (address) {
        vm.startBroadcast();
        Staker router = new Staker(config.usdc);

        vm.stopBroadcast();
        return address(router);
    }
}
