# Smart Contracts

Technical reference for all deployed contracts. Solidity 0.8.26, Cancun EVM, compiled with `via_ir` and 200 optimizer runs.

---

## MiningAgent.sol

ERC-8004 agent identity + mining rig NFT.

### Constants

| Name | Value | Description |
|------|-------|-------------|
| `MAX_SUPPLY` | 10,000 | Maximum mintable rigs |
| `MAX_PRICE` | 0.002 ether | Starting mint price |
| `MIN_PRICE` | 0.0002 ether | Floor mint price |
| `STEP_SIZE` | 100 | Mints per price step |
| `DECAY_NUM` | 95 | Numerator (5% decay) |
| `DECAY_DEN` | 100 | Denominator |
| `CHALLENGE_DURATION` | 20 | SMHL timeout in seconds |
| `MAX_DEADLINE_DELAY` | 5 minutes | Max wallet binding deadline |

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `lpVault` | `address payable` | Fee recipient (set once) |
| `agentCoin` | `address` | AGENT token (set once, for tokenURI) |
| `challengeNonce` | `uint256` | Increments per challenge |
| `nextTokenId` | `uint256` | Next token to mint (starts at 1) |

### Key Functions

| Function | Access | Description |
|----------|--------|-------------|
| `getChallenge(address)` | Anyone | Generate SMHL challenge |
| `mint(string)` | EOA only | Mint rig with SMHL solution |
| `getMintPrice()` | View | Current mint price |
| `setAgentCoin(address)` | Owner (once) | Set AGENT token address |
| `setLPVault(address)` | Owner (once) | Set fee vault address |
| `agentURI(uint256)` | View | Get agent identity URI |
| `setAgentURI(uint256, string)` | Authorized | Set agent identity URI |
| `getMetadata(uint256, string)` | View | Read metadata key |
| `setMetadata(uint256, string, bytes)` | Authorized | Write metadata key |
| `getAgentWallet(uint256)` | View | Get bound wallet |
| `setAgentWallet(uint256, address, uint256, bytes)` | Authorized | Bind wallet (EIP-712) |
| `unsetAgentWallet(uint256)` | Authorized | Remove wallet binding |
| `tokenURI(uint256)` | View | On-chain SVG + JSON |

### Events

```solidity
event MinerMinted(address indexed owner, uint256 indexed tokenId, uint8 rarity, uint16 hashpower);
event AgentCoinSet(address agentCoin);
event LPVaultSet(address lpVault);
event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);
event MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue);
```

---

## AgentCoin.sol

ERC-20 token with built-in proof-of-work mining.

### Constants

| Name | Value | Description |
|------|-------|-------------|
| `MAX_SUPPLY` | 21,000,000e18 | Total token supply |
| `LP_RESERVE` | 2,100,000e18 | 10% for LP |
| `MINEABLE_SUPPLY` | 18,900,000e18 | 90% for mining |
| `BASE_REWARD` | 3e18 | 3 AGENT base reward |
| `ERA_INTERVAL` | 500,000 | Mines per era |
| `REWARD_DECAY_NUM` | 90 | 10% decay per era |
| `REWARD_DECAY_DEN` | 100 | Denominator |
| `ADJUSTMENT_INTERVAL` | 64 | Mines between difficulty adjustments |
| `TARGET_BLOCK_INTERVAL` | 5 | Target blocks between mines |
| `CHALLENGE_DURATION` | 20 | SMHL timeout in seconds |

### Immutable State

| Variable | Type | Description |
|----------|------|-------------|
| `miningAgent` | `IMiningAgent` | NFT contract (immutable) |
| `lpVault` | `address` | LP vault (immutable) |

### Mutable State

| Variable | Type | Description |
|----------|------|-------------|
| `totalMines` | `uint256` | Cumulative mine count |
| `challengeNumber` | `bytes32` | Current challenge (rotates per mine) |
| `miningTarget` | `uint256` | Current difficulty target |
| `lastMineBlockNumber` | `uint256` | Block of last mine |
| `lastAdjustmentBlock` | `uint256` | Block of last difficulty adjustment |
| `minesSinceAdjustment` | `uint256` | Counter for adjustment trigger |
| `totalMinted` | `uint256` | Cumulative minted tokens |
| `smhlNonce` | `uint256` | SMHL challenge rotation nonce |

### Key Functions

| Function | Access | Description |
|----------|--------|-------------|
| `getMiningChallenge()` | View | Current challenge, target, SMHL |
| `mine(uint256, string, uint256)` | EOA only | Submit dual proof + mine |
| `tokenMineCount(uint256)` | View | Mines by token ID |
| `tokenEarnings(uint256)` | View | AGENT earned by token ID |

### Events

```solidity
event Mined(address indexed miner, uint256 indexed tokenId, uint256 reward, uint256 totalMines);
event DifficultyAdjusted(uint256 oldTarget, uint256 newTarget);
```

---

## LPVault.sol

LP accumulator with automated Uniswap V3 deployment and UNCX eternal lock.

### Constants

| Name | Value | Description |
|------|-------|-------------|
| `WETH` | `0x4200...0006` | Base WETH |
| `USDC` | `0x8335...2913` | Base USDC |
| `SWAP_ROUTER` | `0x2626...e481` | Uniswap V3 SwapRouter |
| `POSITION_MANAGER` | `0x03a5...4f1` | Uniswap V3 NonfungiblePositionManager |
| `UNCX_V3_LOCKER` | `0x2312...CC1` | UNCX V3 Locker |
| `LP_DEPLOY_THRESHOLD` | 4.9 ether | Minimum balance to deploy |
| `UNCX_FLAT_FEE` | 0.03 ether | UNCX lock fee |
| `FEE_TIER` | 3000 | 0.3% Uniswap fee tier |

### Key Functions

| Function | Access | Description |
|----------|--------|-------------|
| `receive()` | Anyone | Accept ETH from mints |
| `setAgentCoin(address)` | Owner (once) | Set AGENT token |
| `deployLP(uint256)` | Anyone | Deploy liquidity (one-time) |

### Events

```solidity
event LPDeployed(uint256 positionTokenId, uint256 agentAmount, uint256 usdcAmount);
event AgentCoinSet(address agentCoin);
```

---

## Interfaces

### IMiningAgent

```solidity
interface IMiningAgent is IERC721 {
    function hashpower(uint256 tokenId) external view returns (uint16);
    function agentURI(uint256 agentId) external view returns (string memory);
    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory);
    function getAgentWallet(uint256 agentId) external view returns (address);
    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool);
}
```

### IAgentCoin

```solidity
interface IAgentCoin {
    function tokenMineCount(uint256 tokenId) external view returns (uint256);
    function tokenEarnings(uint256 tokenId) external view returns (uint256);
}
```
