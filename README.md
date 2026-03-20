# Unichain USDC Bridge Hook

A Uniswap v4 hook that bridges USDC across chains via Chainlink CCIP, enabling cross-chain swaps and liquidity operations on the Unichain network.

## Project Overview

This project implements a cross-chain USDC bridge system using Uniswap v4 hooks and Chainlink CCIP. The hook intercepts USDC swaps and liquidity operations on Sepolia, automatically bridging tokens to Unichain and Avalanche with support for arbitrary smart contract execution on destination chains.

**Key Features:**
- Intercepts USDC swaps via Uniswap v4 hooks
- Bridges USDC via Chainlink CCIP to multiple destination chains
- Calculates and deducts CCIP bridge fees (LINK) dynamically
- Collects protocol fees (0.1%) from bridged amounts
- Enforces slippage protection on destination chain
- Supports arbitrary calldata execution on destination contracts
- Works with dynamic fee mode pools

## Project Structure

```
.
├── src/
│   ├── UnichainUSDCBridgeHook.sol      # Main hook contract (Sepolia) - intercepts swaps & bridges USDC
│   ├── USDCBridgeSender.sol             # Chainlink CCIP message sender logic
│   ├── USDCBridgeReceiver.sol           # CCIP receiver on destination chains (Unichain/Avalanche)
│   ├── interfaces/
│   │   └── IStaker.sol                  # Interface for staking contracts on destination
│   └── periphery/
│       ├── LiquidityRouter.sol          # Add/remove liquidity helper
│       ├── SwapRouter.sol               # Swap execution helper
│       ├── Staker.sol                   # Example staking contract for destination chain
│       └── USDCLINKPoolHook.sol         # Helper pool for USDC/LINK swaps (pay bridge fees)
│
├── test/
│   ├── UnichainUSDCBridgeHookTest.t.sol # Main hook tests
│   ├── LiquidityRouterTest.t.sol         # Liquidity router tests
│   ├── SwapRouterTest.t.sol              # Swap router tests
│   ├── DeployUSDCLINKPoolTest.t.sol      # USDC/LINK pool tests
│   └── Mock/
│       ├── USDCMock.sol                  # Mock USDC token for testing
│       ├── USDTMock.sol                  # Mock USDT token for testing
│       └── LINKMock.sol                  # Mock LINK token for testing
│
├── script/
│   ├── HelperConfig.s.sol                # Network configuration
│   ├── Deploy/
│   │   ├── DeployUSDTMock.s.sol           # Deploy mock tokens
│   │   ├── DeployUSDCLINKPool.s.sol       # Deploy USDC/LINK pool for fee swaps
│   │   ├── DeployUSDCLINKPoolHook.s.sol   # Deploy USDC/LINK pool hook
│   │   ├── DeployLiquidityRouter.s.sol    # Deploy liquidity router
│   │   ├── DeploySwapRouter.s.sol         # Deploy swap router
│   │   ├── DeployStaker.s.sol             # Deploy example staker contract
│   │   ├── DeployUnichainUSDCBridgeHook.s.sol   # Deploy main hook (Sepolia)
│   │   ├── DeployUnichainUSDCBridgeReceiver.s.sol # Deploy receiver
│   │   └── DeployUnichainUSDCBridgePoolHook.s.sol # Deploy pool hook variant
│   ├── Testnet/
│   │   ├── AddLiqudityToUSDCLINKPool.s.sol      # Add liquidity to USDC/LINK pool
│   │   ├── AddLiqudityToUSDCBridgeHook.s.sol    # Add liquidity to bridge hook pool
│   │   ├── SwapExactInput.s.sol                 # Execute test swaps
│   │   └── SepoliaUnichainSepoliaTest.s.sol     # Cross-chain test flow
│   └── PostDeploy/
│       ├── SenderPostDeploy.s.sol        # Post-deployment configuration for sender
│       └── ReceiverPostDeploy.s.sol      # Post-deployment configuration for receiver
│
├── Makefile                              # Make commands for deployment and testing
├── foundry.toml                         # Foundry configuration
└── README.md
```

## Tests

Run tests locally with:

```bash
forge test
```

### Test Coverage

| Test File | Purpose |
|-----------|---------|
| **UnichainUSDCBridgeHookTest.t.sol** | Tests core hook functionality: swap interception, CCIP message construction, fee calculation, slippage protection |
| **LiquidityRouterTest.t.sol** | Tests adding/removing liquidity to hook-enabled pools |
| **SwapRouterTest.t.sol** | Tests swap execution through routers |
| **DeployUSDCLINKPoolTest.t.sol** | Tests USDC/LINK pool creation and operations |

## Makefile Commands

### Mock Token Deployment

Deploy mock ERC20 tokens for testing:

```bash
# Sepolia
make deployUSDTMock-sepolia

# Unichain Sepolia
make deployUSDTMock-unichain-sepolia

# Avalanche Fuji
make deployUSDTMock-avalanche-fuji
```

### Pool & Router Deployment (Sepolia)

Deploy Uniswap pools and routers:

```bash
# Deploy USDC/LINK pool (used for paying bridge fees)
make deployUSDCLINKPool-sepolia

# Deploy liquidity router
make deployLiqudityRoute-sepolia

# Deploy swap router
make DeploySwapRouter-sepolia
```

### Bridge Hook Deployment (Sepolia)

Deploy the main USDC bridge hook:

```bash
# Deploy the hook
make deployUnichainUSDCBridgeHook-sepolia

# Deploy pool-integrated variant
make DeployUnichainUSDCBridgePoolHook
```

### Receiver Deployment

Deploy receiver contracts on destination chains:

```bash
# Unichain Sepolia
make deployUSDCBridgeReceiver-unichain-sepolia
make deployStaker-unichain-sepolia

# Avalanche Fuji
make deployUSDCBridgeReceiver-avalanche-fuji
make deployStaker-avalanche-fuji
```

### Post-Deployment Configuration

Configure cross-chain connections after deployment:

```bash
# Configure sender on Sepolia
make SenderPostDeploy

# Configure receiver on Unichain Sepolia
make ReceiverPostDeplo-unichain

# Configure receiver on Avalanche Fuji
make ReceiverPostDeploy-avalanche
```

### Liquidity & Testing

Add liquidity and run test transactions:

```bash
# Add liquidity to USDC/LINK pool
make AddLiqudityToUSDCLINKPool

# Add liquidity to bridge hook pool
make AddLiqudityToUSDCBridgeHook

# Execute test swap
make SwapExactInput

# Cross-chain bridge test (Sepolia → Unichain)
make SepoliaUnichainSepoliaTest
```

## Deployed Contract Addresses

### Sepolia (Source Chain)

| Contract | Address | Description |
|----------|---------|-------------|
| Mock USDT | `0x3428Fb59Fa75E14A1ba6d33161FA69545f8B54aF` | Mock USDT token for testing |
| USDC/LINK Pool Hook | `0x6c5732BbBc18616d415a47C214D5ee3ed56A6000` | Pool for USDC/LINK swaps to pay fees |
| Liquidity Router | `0x2528d4304c99eb62820348cbfd50de3c135cdf7f` | Helper for adding/removing liquidity |
| Swap Router | `0x15cd3d34df632ee9934590f18180249df9d1255b` | Helper for executing swaps |
| **Hook / Sender** | **`0x855b0881580caeed3711cfb6f2f1704f8b6124ce`** | Main USDC bridge hook |

### Unichain Sepolia (Destination Chain)

| Contract | Address | Description |
|----------|---------|-------------|
| Mock USDT | `0xCa3012Aa4b82A70b47D1359d0C14ffc9255eEB72` | Mock USDT token for testing |
| **Receiver** | **`0x0266a43006e3b8ef324e79228de2a48b3a8b631c`** | Receives bridged USDC via CCIP |
| Staker | `0x4ED9f16e42246d3d8CE88fe7B34DD7Deb74B4D05` | Example staking contract |

### Avalanche Fuji (Destination Chain)

| Contract | Address | Description |
|----------|---------|-------------|
| Mock USDT | `0xf4365ea16cf834c069fdeafee141303b5ad4a267` | Mock USDT token for testing |
| **Receiver** | **`0x75ef33a278b30529e083af180edfe17f5b34f49d`** | Receives bridged USDC via CCIP |
| Staker | `0x9cbe0c41b05b57c7ef203a6e3ff0831a8f289b0f` | Example staking contract |

## How It Works

### 1. **Swap Flow**

User initiates a swap involving USDC on Sepolia:

```
User → SwapRouter → UnichainUSDCBridgeHook (beforeSwap)
  ↓
Hook detects USDC output
  ↓
Calculates bridge fee (LINK needed for CCIP)
  ↓
Swaps USDC → LINK on USDC/LINK pool to cover fees
  ↓
Constructs CCIP message with destination chain selector
  ↓
Sends message to CCIP router
  ↓
Message routed to destination chain
```

### 2. **Destination Chain Execution**

CCIP router delivers message to receiver on destination (Unichain/Avalanche):

```
CCIPRouter → USDCBridgeReceiver
  ↓
Validates sender & source chain
  ↓
Extracts USDC amount and arbitrary calldata
  ↓
Calls destination contract (e.g., Staker) with data
  ↓
Staker executes arbitrary logic (e.g., stake tokens)
```

### 3. **Fee Structure**

- **Base Fee**: 10% of bridged amount (configurable)
- **Protocol Fee**: 0.1% (collected for protocol)
- **CCIP Fee**: Paid in LINK from swapping portion of USDC

## Key Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `BASE_FEE` | 1000 (10%) | Bridge fee percentage |
| `PROTOCOL_FEE` | 10 (0.1%) | Protocol fee percentage |
| `DENOMINATOR` | 10,000 | Fee calculation divisor |

## Environment Setup

Create a `.env` file with:

```bash
SEPOLIA_RPC_URL=
UNICHAIN_SEPOLIA_RPC_URL=
AVALANCHE_FUJI_RPC_URL=
ETHERSCAN_API_KEY=
SENDER=<your-wallet-address>
```

## Development

### Build
```bash
forge build
```

### Test
```bash
forge test
```

### Test with Gas Report
```bash
forge test --gas-report
```

### Format
```bash
forge fmt
```

## Architecture Decisions

- **Uniswap v4 Hooks**: Used for transparent interception of swaps without protocol modification
- **Chainlink CCIP**: Provides reliable cross-chain messaging with native token bridging
- **Dynamic Fee Mode**: Allows hooks to adjust fees per transaction based on bridge costs
- **Arbitrary Calldata**: Enables flexible destination chain logic (staking, swaps, etc.)

## Security Considerations

- Slippage protection enforced on destination chain with `minAmountOut`
- Message validation against configured senders per chain
- Failed message handling with callback mechanism
- Protocol fees collected separately to prevent fund loss
- LINK reserves managed for CCIP fee coverage

## License

MIT
