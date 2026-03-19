include .env

#unichain sepolia
deployUSDTMock-unichain-sepolia:; forge script script/Deploy/DeployUSDTMock.s.sol --rpc-url ${UNICHAIN_SEPOLIA_RPC_URL} --broadcast --account devKey --verify --verifier blockscout --verifier-url https://unichain-sepolia.blockscout.com/api/ -vvvv
deployStaker-unichain-sepolia:; forge script script/Deploy/DeployStaker.s.sol --rpc-url ${UNICHAIN_SEPOLIA_RPC_URL} --broadcast --account devKey --verify --verifier blockscout --verifier-url https://unichain-sepolia.blockscout.com/api/ -vvvv

#sepolia
deployUSDTMock-sepolia:; forge script script/Deploy/DeployUSDTMock.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv

deployUSDCLINKPool-sepolia:; forge script script/Deploy/DeployUSDCLINKPool.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 10 -vvvv

deployLiqudityRoute-sepolia:; forge script script/Deploy/DeployLiquidityRouter.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 10 -vvvv

deployUnichainUSDCBridgeHook-sepolia:; forge script script/Deploy/DeployUnichainUSDCBridgeHook.s.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --verify --etherscan-api-key ${ETHERSCAN_API_KEY} --delay 10 -vvvv
#sepoli-tests
AddLiqudityToUSDCLINKPool:; forge script script/Testnet/AddLiqudityToUSDCLINKPool.s.sol:AddLiqudityToUSDCLINKPool --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv