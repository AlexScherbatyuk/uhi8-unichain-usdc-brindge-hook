include .env

#unichain sepolia
deployUSDTMock-unichain-sepolia:; forge script script/Deploy/DeployUSDTMock.s.sol --rpc-url ${UNICHAIN_SEPOLIA_RPC_URL} --broadcast --account devKey --verify --verifier blockscout --verifier-url https://unichain-sepolia.blockscout.com/api/ -vvvv

deployStaker-unichain-sepolia:; forge script script/Deploy/DeployStaker.s.sol --rpc-url ${UNICHAIN_SEPOLIA_RPC_URL} --broadcast --account devKey --verify --verifier blockscout --verifier-url https://unichain-sepolia.blockscout.com/api/ -vvvv

deployUSDCBridgeReceiver-unichain-sepolia:; forge script script/Deploy/DeployUSDCBridgeReceiver.s.sol --rpc-url ${UNICHAIN_SEPOLIA_RPC_URL} --broadcast --account devKey --verify --verifier blockscout --verifier-url https://unichain-sepolia.blockscout.com/api/ -vvvv


#sepolia
deployUSDTMock-sepolia:; forge script script/Deploy/DeployUSDTMock.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv

deployUSDCLINKPool-sepolia:; forge script script/Deploy/DeployUSDCLINKPool.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 10 -vvvv

deployLiqudityRoute-sepolia:; forge script script/Deploy/DeployLiquidityRouter.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 10 -vvvv

deployUnichainUSDCBridgeHook-sepolia:; forge script script/Deploy/DeployUnichainUSDCBridgeHook.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --sender ${SENDER} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 30 -vvvv

DeployUnichainUSDCBridgePoolHook:; forge script script/Deploy/DeployUnichainUSDCBridgePoolHook.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --sender ${SENDER} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 30 -vvvv

DeploySwapRouter-sepolia:; forge script script/Deploy/DeploySwapRouter.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --sender ${SENDER} --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 10 -vvvv
#avalanche sepolia
deployUSDTMock-avalanche-fuji:; forge script script/Deploy/DeployUSDTMock.s.sol --rpc-url ${AVALANCHE_FUJI_RPC_URL} --broadcast --account devKey --verify --verifier etherscan --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv

deployStaker-avalanche-fuji:; forge script script/Deploy/DeployStaker.s.sol --rpc-url ${AVALANCHE_FUJI_RPC_URL} --broadcast --account devKey --verify --verifier etherscan --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv

deployUSDCBridgeReceiver-avalanche-fuji:; forge script script/Deploy/DeployUSDCBridgeReceiver.s.sol --rpc-url ${AVALANCHE_FUJI_RPC_URL} --broadcast --account devKey --verify --verifier etherscan --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv

#sepoli-post-deploy
AddLiqudityToUSDCLINKPool:; forge script script/Testnet/AddLiqudityToUSDCLINKPool.s.sol:AddLiqudityToUSDCLINKPool --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey -vvvv

AddLiqudityToUSDCBridgeHook:; 
	cast send 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 "approve(address,uint256)" 0x2528d4304c99eb62820348cbfd50de3c135cdf7f 1000000000000000000 --rpc-url ${SEPOLIA_RPC_URL} --account devKey
	cast send 0x3428Fb59Fa75E14A1ba6d33161FA69545f8B54aF "approve(address,uint256)" 0x2528d4304c99eb62820348cbfd50de3c135cdf7f 1000000000000000000 --rpc-url ${SEPOLIA_RPC_URL} --account devKey
	forge script script/Testnet/AddLiqudityToUSDCBridgeHook.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --sender ${SENDER} -vvvv

SwapExactInput:
	cast send 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 "approve(address,uint256)" 0x15cd3d34df632ee9934590f18180249df9d1255b 1000000000000000000 --rpc-url ${SEPOLIA_RPC_URL} --account devKey
	forge script script/Testnet/SwapExactInput.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --sender ${SENDER} -vvvv

SenderPostDeploy:; forge script script/PostDeploy/SenderPostDeploy.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey -vvvv

#sepolia-unichain-post-deploy
ReceiverPostDeplo-unichain:;  forge script script/PostDeploy/ReceiverPostDeploy.s.sol --rpc-url ${UNICHAIN_SEPOLIA_RPC_URL} --broadcast --account devKey -vvvv

#sepolia-unichain-post-deploy
ReceiverPostDeploy-avalanche:;  forge script script/PostDeploy/ReceiverPostDeploy.s.sol --rpc-url ${AVALANCHE_FUJI_RPC_URL} --broadcast --account devKey -vvvv

#sepoli->unichain-sepoli-test
SepoliaUnichainSepoliaTest:
	cast send 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 "transfer(address,uint256)" 0x855b0881580caeed3711cfb6f2f1704f8b6124ce 1000000 --rpc-url ${SEPOLIA_RPC_URL} --account devKey
	cast send 0x779877A7B0D9E8603169DdbD7836e478b4624789 "transfer(address,uint256)" 0x855b0881580caeed3711cfb6f2f1704f8b6124ce 1000000000000000000 --rpc-url ${SEPOLIA_RPC_URL} --account devKey
	forge script script/Testnet/SepoliaUnichainSepoliaTest.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey -vvvv