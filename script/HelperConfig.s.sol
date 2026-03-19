// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {USDCMock} from "test/Mock/USDCMock.sol";
import {USDTMock} from "test/Mock/USDTMock.sol";
import {LINKMock} from "test/Mock/LINKMock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address[] ccipRouters;
        address[] linkTokens;
        uint64[] destinationChainIds;
        uint64[] destinationChainSelectors;
        address usdc;
        address usdt;
        address poolManager;
        address usdcLinkPoolHook;
        address liquidityRouter;
    }

    uint8 public constant DECIMALS = 6;

    NetworkConfig private activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 1301) {
            activeNetworkConfig = getUnichainSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        uint64[] memory destinationChainIds = new uint64[](2);
        destinationChainIds[0] = 11155111; // Sepolia
        destinationChainIds[1] = 1301; // Unichain Sepolia

        uint64[] memory destinationChainSelectors = new uint64[](2);
        destinationChainSelectors[0] = 16015286601757825753; // Ethereum Sepolia
        destinationChainSelectors[1] = 14135854469784514356; // Unichain Sepolia

        address[] memory ccipRouters = new address[](2);
        ccipRouters[0] = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59; // CCIP Router Sepolia
        ccipRouters[1] = 0x5b7D7CDf03871dc9Eb00830B027e70A75bd3DC95; // CCIP Router Unichain Sepolia

        address[] memory linkTokens = new address[](2);
        linkTokens[0] = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // Link Token Sepolia
        linkTokens[1] = 0xda40816f278Cd049c137F6612822D181065EBfB4; // Link Token Unichain Sepolia

        return NetworkConfig({
            ccipRouters: ccipRouters, // CCIP Router Sepolia
            linkTokens: linkTokens, // Link Token Sepolia
            destinationChainSelectors: destinationChainSelectors,
            destinationChainIds: destinationChainIds,
            usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, // USDC Token Sepolia
            usdt: 0x3428Fb59Fa75E14A1ba6d33161FA69545f8B54aF, // USDT Mock Sepolia
            poolManager: 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543, // PoolManager Sepolia
            usdcLinkPoolHook: 0x6c5732BbBc18616d415a47C214D5ee3ed56A6000,
            liquidityRouter: 0x33C88D1d00369455392d1AC33D5145B77fEa811B
        });
    }

    function getUnichainSepoliaConfig() public pure returns (NetworkConfig memory) {
        uint64[] memory destinationChainIds = new uint64[](2);
        destinationChainIds[0] = 11155111; // Sepolia
        destinationChainIds[1] = 1301; // Unichain Sepolia

        uint64[] memory destinationChainSelectors = new uint64[](2);
        destinationChainSelectors[0] = 16015286601757825753; // Ethereum Sepolia
        destinationChainSelectors[1] = 14135854469784514356; // Unichain Sepolia

        address[] memory ccipRouters = new address[](2);
        ccipRouters[0] = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59; // CCIP Router Sepolia
        ccipRouters[1] = 0x5b7D7CDf03871dc9Eb00830B027e70A75bd3DC95; // CCIP Router Unichain Sepolia

        address[] memory linkTokens = new address[](2);
        linkTokens[0] = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // Link Token Sepolia
        linkTokens[1] = 0xda40816f278Cd049c137F6612822D181065EBfB4; // Link Token Unichain Sepolia

        return NetworkConfig({
            ccipRouters: ccipRouters, // CCIP Router Sepolia
            linkTokens: linkTokens, // Link Token Sepolia
            destinationChainSelectors: destinationChainSelectors,
            destinationChainIds: destinationChainIds,
            usdc: 0x31d0220469e10c4E71834a79b1f276d740d3768F, // USDC Token Unichain Sepolia
            usdt: 0xCa3012Aa4b82A70b47D1359d0C14ffc9255eEB72, // USDT Mock on Unichain Sepolia
            poolManager: 0x00B036B58a818B1BC34d502D3fE730Db729e62AC, // PoolManager Unichain Sepolia
            usdcLinkPoolHook: address(0),
            liquidityRouter: address(0)
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.destinationChainIds.length > 0) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        USDCMock mUSDC = new USDCMock("USDC", "USDC", 6);
        USDTMock mUSDT = new USDTMock("USDT", "USDT", 6);
        LINKMock mLINKMock = new LINKMock("LINK", "LINK", 18);

        vm.stopBroadcast();

        uint64[] memory destinationChainIds = new uint64[](2);
        destinationChainIds[0] = 11155111; // Sepolia
        destinationChainIds[1] = 1301; // Unichain Sepolia

        uint64[] memory destinationChainSelectors = new uint64[](2);
        destinationChainSelectors[0] = 16015286601757825753; // Ethereum Sepolia
        destinationChainSelectors[1] = 14135854469784514356; // Unichain Sepolia

        address[] memory ccipRouters = new address[](2);
        ccipRouters[0] = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59; // CCIP Router Sepolia
        ccipRouters[1] = 0x5b7D7CDf03871dc9Eb00830B027e70A75bd3DC95; // CCIP Router Unichain Sepolia

        address[] memory linkTokens = new address[](2);
        linkTokens[0] = address(mLINKMock); // Link Token Sepolia
        linkTokens[1] = address(mLINKMock); // Link Token Unichain Sepolia

        return NetworkConfig({
            ccipRouters: ccipRouters, // CCIP Router Sepolia
            linkTokens: linkTokens, // Link Token Sepolia
            destinationChainSelectors: destinationChainSelectors,
            destinationChainIds: destinationChainIds,
            usdc: address(mUSDC),
            usdt: address(mUSDT),
            poolManager: 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408,
            usdcLinkPoolHook: address(0),
            liquidityRouter: address(0)
        });
    }

    function getConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
