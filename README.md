### Sender Sepoli 0xe9fEcbEC0F1B7C820A33354fC564F7A3753c032d

### Staker Unichain Sepolia 0x4ED9f16e42246d3d8CE88fe7B34DD7Deb74B4D05

## Receiver Unichain Sepolia 0x045e5621C5C0ed32958799aDaceB522ffCd72F0d

####

## Sender 0xE5bBCcDd68f0a0cDC3Ac08d4D19a1B7E30306042 Avilanche Fuji

### Staker Unichain Sepolia 0x4ED9f16e42246d3d8CE88fe7B34DD7Deb74B4D05

## Receiver Unichain Sepolia 0x045e5621C5C0ed32958799aDaceB522ffCd72F0d


## Sepolia Staker 0xCF589cD768a02a1bdafE887578CC657952B9B933
## Sepolia Receiver 0x94a47C11316f02DB4EB9098B82926dfd8408Ca9B


###

## Sepolia Sender 0x6d714CBc770f7B86bb102d07EC3E16DB68A467cf
## Avalanche Staker 0x72F322567Ed1cFeA00A98630252AF0011D7F240c
## Avalanche Receiver 0x71F22b9f94b70d922e6E26741d8D44B1Fde302Ae


## last chance
### Staker Unichain Sepolia 0x113f97dB1Fa636667700747B8Cf07454bEdB0Fb0
### Receiver Unichain Sepolia 0xc95e1983102317eB7c7156FfEa82ADd322760DB7
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
| Hook / Sender | 0x7bdc5e441da38e15d7c0911acf96a04fb67624ce | The main project bridge hook |

### Unichain Sepolia

| Contract Name | Address | Description |
|---|---|---|
| Mock USDT | 0xCa3012Aa4b82A70b47D1359d0C14ffc9255eEB72 | Mock USDT token for testing |
| Receiver | 0x0266a43006e3b8ef324e79228de2a48b3a8b631c | Cross-chain receiver |
| Staker   | 0x4ED9f16e42246d3d8CE88fe7B34DD7Deb74B4D05 | Staking contract example for arbitary call on unichain |


### Avalanche
| Contract Name | Address | Description |
|---|---|---|
| Mock USDT | 0xf4365ea16cf834c069fdeafee141303b5ad4a267 | Mock USDT token for testing |
| Receiver | 0x607717140bc2ef8d28deaa35ab412db151719e89 | Cross-chain receiver |
| Staker   | 0x72F322567Ed1cFeA00A98630252AF0011D7F240c | Staking contract example for arbitary call on unichain |
