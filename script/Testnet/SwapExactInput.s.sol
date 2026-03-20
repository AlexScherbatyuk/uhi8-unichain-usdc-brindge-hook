// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {UnichainUSDCBridgeHook} from "src/UnichainUSDCBridgeHook.sol";
import {SwapRouter} from "src/periphery/SwapRouter.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

contract SwapExactInput is Script {
    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    struct MessageData {
        address beneficiary; // contract to call on Unichain (e.g. vault, router)
        uint8 strategy; // arbitrary calldata to forward (can be empty)
        uint256 minAmountOut; // slippage guard enforced on destination
        bytes data;
    }

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
        bytes memory hookData = abi.encode(
            0x667c1aBD4E25BE048b8217F90Fc576780CCa8218,
            UnichainUSDCBridgeHook.MessageData({
                beneficiary: 0x667c1aBD4E25BE048b8217F90Fc576780CCa8218, strategy: 0, minAmountOut: 0, data: ""
            }),
            false
        );
        vm.startBroadcast();
        SwapRouter(config.swapRouter)
            .swap({
                key: PoolKey({
                    currency0: Currency.wrap(config.usdc),
                    currency1: Currency.wrap(config.usdt),
                    fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
                    tickSpacing: 60,
                    hooks: IHooks(config.srcChainSender) // Main Hook / Sender
                }),
                amountIn: -int128(int256(amount)),
                zeroForOne: true,
                minAmountOut: 0,
                hookData: hookData
            });

        //  function swap(PoolKey memory key, uint256 amountIn, bool zeroForOne, uint256 minAmountOut)
        vm.stopBroadcast();
    }
}
