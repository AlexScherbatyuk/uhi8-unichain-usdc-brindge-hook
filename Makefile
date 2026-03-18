include .env

deployUSDTMock-unichain-sepolia:; forge script script/Deploy/DeployUSDTMock.sol --rpc-url ${UNICHAIN_SEPOLIA_RPC_URL} --broadcast --account devKey --verify --verifier blockscout --verifier-url https://unichain-sepolia.blockscout.com/api/ -vvvv
deployUSDTMock-sepolia:; forge script script/Deploy/DeployUSDTMock.sol --rpc-url ${SEPOLIA_RPC_URL} --broadcast --account devKey --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv