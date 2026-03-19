### Sender Avelanche 0xe9d113Ed45f4E42b182d66A1233101FeCfA190ea

### Staker Sepolia 0x4f45c760977A2C57E135eDD71D32e45A756BDA7a

## Receiver Sepoli 0x41FD4526d333c54810078f59f3E7b7f642e7f5ba



##TODO LIST


### Hook
1. Implement basice hook setup with after swap hook and test swap. ✅
   
### Sender
1. Implemt cross-chain messeggae + USDC sender and test on testnet. ✅

### Receiver
1. Implement cross-chain receiver + stake (simple for tests) contract to receive USDC and stake it as payload instracted. ✅



## Local tests
## Fork tests for cros-chain Sepolia/Unichain
### Predeploid Sepolia and Unichain contracts: Sepolia (Pool, Hook), Unichain (Receiver) 


## Deployed Contracts

### Sepolia

| Contract Name | Address | Description |
|---|---|---|
| Mock USDT | 0x3428Fb59Fa75E14A1ba6d33161FA69545f8B54aF | Mock USDT token, examplary token1 for main hook's pool |
| USDC/LINK Pool Hook | 0x6c5732BbBc18616d415a47C214D5ee3ed56A6000 | USDC/LINK Pool Hook is used to swap usdc to link, to pay Chainlink fee |
| LiquidityRouter | 0x33c88d1d00369455392d1ac33d5145b77fea811b | Is used do add liqudity to project pools |
| Hook | 0x0ca1f656c3ff9504ee90cf19629d5c64f849e4ce | The main project bridge hook |
<!--| Staker/Sender | 0x4f45c760977A2C57E135eDD71D32e45A756BDA7a | Cross-chain message sender contract |-->

### Unichain Sepolia

| Contract Name | Address | Description |
|---|---|---|
| Mock USDT | 0xCa3012Aa4b82A70b47D1359d0C14ffc9255eEB72 | Mock USDT token for testing |
| Receiver | 0x41FD4526d333c54810078f59f3E7b7f642e7f5ba | Cross-chain receiver + stake contract |
| Staker   | 0x4ED9f16e42246d3d8CE88fe7B34DD7Deb74B4D05 | Staking contract example for arbitary call on unichain |