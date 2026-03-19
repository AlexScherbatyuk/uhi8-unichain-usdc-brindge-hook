// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Script} from "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {UnichainUSDCBridgeHook} from "src/UnichainUSDCBridgeHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployUnichainUSDCBridgeHook is Script {
    // https://getfoundry.sh/guides/deterministic-deployments-using-create2/#getting-started
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // // https://docs.uniswap.org/contracts/v4/deployments#base-sepolia-84532
    // address internal constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;

    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    function run() external {
        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();
        // Hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(
            config.poolManager,
            address(config.usdc),
            address(config.linkTokens[0]),
            address(config.ccipRouters[0]),
            address(config.usdcLinkPoolHook),
            config.destinationChainSelectors[0]
        );
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(UnichainUSDCBridgeHook).creationCode, constructorArgs);

        vm.startBroadcast();

        // Deploy the hook using CREATE2
        UnichainUSDCBridgeHook unichainUSDCBridgeHook = new UnichainUSDCBridgeHook{salt: salt}(
            IPoolManager(config.poolManager),
            address(config.usdc),
            address(config.linkTokens[0]),
            address(config.ccipRouters[0]),
            address(config.usdcLinkPoolHook),
            config.destinationChainSelectors[0]
        );
        require(address(unichainUSDCBridgeHook) == hookAddress, "PointsHookScript: hook address mismatch");

        vm.stopBroadcast();
    }
}
