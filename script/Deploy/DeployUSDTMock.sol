// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {USDTMock} from "test/Mock/USDTMock.sol";
import {Script} from "forge-std/Script.sol";

contract DeployUSDTMock is Script {
    function run() external {
        deploy();
    }

    function deploy() public returns (address) {
        vm.startBroadcast();
        USDTMock token = new USDTMock("USDT", "USDT", 6);
        vm.stopBroadcast();
        return address(token);
    }
}
