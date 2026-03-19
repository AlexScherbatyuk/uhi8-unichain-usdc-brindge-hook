// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Script} from "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {USDCLINKPoolHook} from "src/periphery/USDCLINKPoolHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployUSDCLINKPoolHook is Script {
    // https://getfoundry.sh/guides/deterministic-deployments-using-create2/#getting-started
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    function run() external {
        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();
        deploy(config.poolManager);
    }

    function deploy(address poolManager) public returns (address) {
        // Hook contracts must have specific flags encoded in the address
        // beforeInitialize flag = 0x0001
        uint160 flags = Hooks.BEFORE_INITIALIZE_FLAG;

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(poolManager);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(USDCLINKPoolHook).creationCode, constructorArgs);
        vm.startBroadcast();
        // Deploy the hook using CREATE2
        USDCLINKPoolHook uSDCLINKPoolHook = new USDCLINKPoolHook{salt: salt}(IPoolManager(poolManager));
        require(address(uSDCLINKPoolHook) == hookAddress, "NoOpHook: hook address mismatch");

        vm.stopBroadcast();
        return hookAddress;
    }
}
