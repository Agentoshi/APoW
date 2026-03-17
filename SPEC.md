# AgentCoin ($AGENT) — Implementation Spec

## Overview

Mineable ERC-20 on Base powered by Proof of Agentic Work (PoAW). Three contracts + one library. Every mining rig NFT doubles as an on-chain AI agent identity (ERC-8004).

## Contract 1: MiningAgent.sol — ERC-8004 Mining Rig Agent Identity

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
```

**Imports:** OpenZeppelin ERC721Enumerable, Ownable, ReentrancyGuardTransient, EIP712, SignatureChecker

**Inheritance:** `ERC721Enumerable, Ownable, ReentrancyGuardTransient, EIP712, IMiningAgent`

**Constants:**
- `MAX_SUPPLY = 10_000`
- `MAX_PRICE = 0.002 ether` (~$4.63 at $2,300/ETH)
- `MIN_PRICE = 0.000217 ether` (~$0.50 floor)
- `STEP_SIZE = 100` (price updates every 100 mints)
- `DECAY_NUM = 95` / `DECAY_DEN = 100` (5% decay per step)
- `CHALLENGE_DURATION = 20` (seconds)
- `AGENT_WALLET_SET_TYPEHASH` — EIP-712 type hash for `AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)`
- `MAX_DEADLINE_DELAY = 5 minutes`
- `RESERVED_KEY_HASH = keccak256("agentWallet")`

**State:**
- `lpVault` — address payable, set once by owner
- `agentCoin` — address, set once by owner (for dynamic NFT stats)
- `challengeNonce` — uint256, increments per getChallenge call
- `nextTokenId` — uint256, starts at 1

**Per-token storage:**
- `mapping(uint256 => uint16) public hashpower` — 100=1x, 150=1.5x, 200=2x, 300=3x, 500=5x
- `mapping(uint256 => uint8) public rarity` — 0=Common, 1=Uncommon, 2=Rare, 3=Epic, 4=Mythic
- `mapping(uint256 => uint256) public mintBlock` — block number at mint

**Challenge storage:**
- `mapping(address => bytes32) public challengeSeeds` — seed per address
- `mapping(address => uint256) public challengeTimestamps` — when challenge was requested

**ERC-8004 Agent Identity storage:**
- `mapping(uint256 => string) private _agentURIs` — per-token agent identity document URI
- `mapping(uint256 => mapping(string => bytes)) private _metadata` — per-token key-value metadata (the key `"agentWallet"` is reserved)

**SMHL Challenge struct:**
```solidity
struct SMHLChallenge {
    uint16 targetAsciiSum;  // sum of ASCII values of first N chars
    uint8 firstNChars;       // N (how many chars to sum)
    uint8 wordCount;         // exact word count required
    uint8 charPosition;      // position to check (0-indexed)
    uint8 charValue;         // ASCII value required at that position
    uint16 totalLength;      // exact string length required
}
```

**Events:**
- `MinerMinted(address indexed owner, uint256 indexed tokenId, uint8 rarity, uint16 hashpower)`
- `AgentCoinSet(address agentCoin)`
- `LPVaultSet(address lpVault)`
- `Registered(uint256 indexed agentId, string agentURI, address indexed owner)` — ERC-8004
- `URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy)` — ERC-8004
- `MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue)` — ERC-8004

**Constructor:**
```solidity
constructor() ERC721("AgentCoin Miner", "MINER") Ownable(msg.sender) EIP712("MiningAgent", "1") {}
```

### Core Functions

`getChallenge(address minter) external returns (SMHLChallenge memory)`:
- Stores `challengeSeeds[minter] = keccak256(abi.encodePacked(minter, block.prevrandao, challengeNonce++))`
- Stores `challengeTimestamps[minter] = block.timestamp`
- Derives challenge params deterministically from seed (see `_deriveChallenge`)
- Returns the challenge

`mint(string calldata solution) external payable nonReentrant`:
- `require(msg.sender == tx.origin, "No contracts")`
- `require(nextTokenId <= MAX_SUPPLY, "Sold out")`
- `require(challengeTimestamps[msg.sender] > 0, "No challenge")`
- `require(block.timestamp <= challengeTimestamps[msg.sender] + CHALLENGE_DURATION, "Expired")`
- `require(lpVault != address(0), "LPVault not set")`
- `require(msg.value >= getMintPrice(), "Insufficient fee")`
- Reconstruct challenge from `challengeSeeds[msg.sender]`, verify SMHL
- Clear challenge data (delete seed + timestamp)
- Determine rarity from `keccak256(abi.encodePacked(block.prevrandao, msg.sender, tokenId))`
- Mint NFT, set hashpower/rarity/mintBlock
- **ERC-8004:** Set `_metadata[tokenId]["agentWallet"] = abi.encodePacked(msg.sender)`, emit `Registered`
- Emit `MinerMinted`
- Forward full `msg.value` to `lpVault`

`getMintPrice() public view returns (uint256)`:
- Exponential decay: `price = MAX_PRICE * (95/100)^steps` where `steps = minted / STEP_SIZE`
- Floored at `MIN_PRICE`
- Starts at 0.002 ETH (~$4.63), drops 5% every 100 mints (~$11.1k total revenue)

`setAgentCoin(address) external onlyOwner` — one-time set, zero-address check
`setLPVault(address payable) external onlyOwner` — one-time set, zero-address check

### ERC-8004: Agent Identity Functions

`agentURI(uint256 agentId) external view returns (string memory)`:
- Requires token exists (`_requireOwned`)
- Returns the agent's identity document URI (separate from `tokenURI`)

`setAgentURI(uint256 agentId, string calldata newURI) external`:
- Requires caller is owner, approved, or operator (`_isAuthorized`)
- Sets `_agentURIs[agentId]`, emits `URIUpdated`

`getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory)`:
- Requires token exists
- Returns `_metadata[agentId][metadataKey]`

`setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external`:
- Requires caller is authorized
- **Rejects reserved key:** `require(keccak256(bytes(metadataKey)) != RESERVED_KEY_HASH, "Use setAgentWallet")`
- Sets `_metadata[agentId][metadataKey]`, emits `MetadataSet`

`getAgentWallet(uint256 agentId) external view returns (address)`:
- Reads `_metadata[agentId]["agentWallet"]`
- Returns `address(0)` if empty, otherwise decodes `bytes20` → `address`

`setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external`:
- Requires caller is authorized, `newWallet != address(0)`
- Deadline validation: `deadline >= block.timestamp` and `deadline <= block.timestamp + MAX_DEADLINE_DELAY`
- EIP-712 verification: builds struct hash from `(agentId, newWallet, owner, deadline)`, computes `_hashTypedDataV4(structHash)`, verifies via `SignatureChecker.isValidSignatureNow(newWallet, digest, signature)` — supports both ECDSA and ERC-1271 smart contract wallets
- Stores `abi.encodePacked(newWallet)` in metadata, emits `MetadataSet`

`unsetAgentWallet(uint256 agentId) external`:
- Requires caller is authorized
- Deletes `_metadata[agentId]["agentWallet"]`, emits `MetadataSet` with empty value

`isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool)`:
- Utility function exposing OZ's internal `_isAuthorized`

### Transfer Hook

`_update(address to, uint256 tokenId, address auth) internal override(ERC721Enumerable)`:
- Calls `super._update()` (ERC721Enumerable bookkeeping)
- On transfer (not mint/burn): `delete _metadata[tokenId]["agentWallet"]`
- Ensures agent wallet binding is cleared when NFT changes hands

### Internal Functions

`_deriveChallenge(bytes32 seed) internal pure returns (SMHLChallenge memory)`:
- `firstNChars = 5 + (seed[0] % 6)` → range 5-10
- `wordCount = 3 + (seed[2] % 5)` → range 3-7
- `totalLength = 20 + (uint16(seed[5]) % 31)` → range 20-50
- `charPosition = seed[3] % totalLength`
- `charValue = 97 + (seed[4] % 26)` → lowercase a-z
- `targetAsciiSum = 400 + (uint16(seed[1]) * 3)` → clamped to feasible range

`_verifySMHL(string calldata solution, SMHLChallenge memory c) internal pure returns (bool)`:
- Check `bytes(solution).length == c.totalLength`
- Check char at position == `c.charValue`
- Sum ASCII of first N chars, check == `c.targetAsciiSum`
- Count words (space-separated), check == `c.wordCount`

`_determineRarity(bytes32 seed) internal pure returns (uint8 rarityTier, uint16 hp)`:
- `roll = uint256(seed) % 100`
- `roll < 1` → Mythic (4), hp=500
- `roll < 5` → Epic (3), hp=300
- `roll < 15` → Rare (2), hp=200
- `roll < 40` → Uncommon (1), hp=150
- else → Common (0), hp=100

### Storage Layout

| Slot | Variable | Type |
|------|----------|------|
| 0-1 | _name, _symbol | string (ERC721) |
| 2-5 | _owners, _balances, _tokenApprovals, _operatorApprovals | mappings (ERC721) |
| 6-9 | _ownedTokens, _ownedTokensIndex, _allTokens, _allTokensIndex | ERC721Enumerable |
| 10 | _owner | address (Ownable) |
| 11-12 | _nameFallback, _versionFallback | string (EIP712) |
| 13 | lpVault | address payable |
| 14 | agentCoin | address |
| 15 | challengeNonce | uint256 |
| 16 | nextTokenId | uint256 |
| 17-19 | hashpower, rarity, mintBlock | mappings |
| 20-21 | challengeSeeds, challengeTimestamps | mappings |
| 22 | _agentURIs | mapping(uint256 => string) |
| 23 | _metadata | mapping(uint256 => mapping(string => bytes)) |

## Contract 2: AgentCoin.sol — ERC-20 + PoAW Mining

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
```

**Imports:** OpenZeppelin ERC20, Ownable, ReentrancyGuardTransient

**Inheritance:** `ERC20, Ownable, ReentrancyGuardTransient, IAgentCoin`

**Constants:**
- `MAX_SUPPLY = 21_000_000e18`
- `LP_RESERVE = 2_100_000e18` (10%)
- `MINEABLE_SUPPLY = MAX_SUPPLY - LP_RESERVE` (18,900,000e18)
- `BASE_REWARD = 3e18` (3 AGENT)
- `ERA_INTERVAL = 500_000` (mines per era)
- `REWARD_DECAY_NUM = 90` / `REWARD_DECAY_DEN = 100`
- `ADJUSTMENT_INTERVAL = 64` (mines between difficulty adjustments)
- `TARGET_BLOCK_INTERVAL = 5` (1 mine per 5 Base blocks = ~10s)
- `CHALLENGE_DURATION = 20` (seconds for SMHL)

**Immutable state:**
- `miningAgent` — `IMiningAgent` (set in constructor, immutable)
- `lpVault` — `address` (set in constructor, immutable)

**Mutable state:**
- `totalMines` — uint256
- `challengeNumber` — bytes32 (rotates each mine)
- `miningTarget` — uint256 (difficulty — hash must be below this)
- `lastMineBlockNumber` — uint256
- `lastAdjustmentBlock` — uint256
- `minesSinceAdjustment` — uint256
- `totalMinted` — uint256 (tracks minted supply, excludes LP reserve)
- `smhlNonce` — uint256 (increments each mine)

**Per-token tracking (for dynamic NFT metadata):**
- `mapping(uint256 => uint256) public tokenMineCount`
- `mapping(uint256 => uint256) public tokenEarnings`

**Events:**
- `Mined(address indexed miner, uint256 indexed tokenId, uint256 reward, uint256 totalMines)`
- `DifficultyAdjusted(uint256 oldTarget, uint256 newTarget)`

**Constructor:**
```solidity
constructor(address _miningAgent, address _lpVault) ERC20("AgentCoin", "AGENT") Ownable(msg.sender)
```
- Zero-address checks on both params
- Sets `miningAgent = IMiningAgent(_miningAgent)` (immutable)
- Sets `lpVault = _lpVault` (immutable)
- `challengeNumber = keccak256("AgentCoin Genesis")`
- `miningTarget = type(uint256).max >> 16` (easy initial difficulty)
- `lastMineBlockNumber = block.number`
- `lastAdjustmentBlock = block.number`
- Mints `LP_RESERVE` to `_lpVault`

**Functions:**

`getMiningChallenge() external view returns (bytes32 challenge, uint256 target, SMHLChallenge memory smhl)`:
- Returns current `challengeNumber`, `miningTarget`, and SMHL derived from `keccak256(challengeNumber, smhlNonce)`

`mine(uint256 nonce, string calldata smhlSolution, uint256 tokenId) external nonReentrant`:
- `require(msg.sender == tx.origin, "No contracts")`
- `require(block.number > lastMineBlockNumber, "One mine per block")`
- `require(miningAgent.ownerOf(tokenId) == msg.sender, "Not your miner")`
- Verify SMHL solution against current challenge
- Verify hash: `uint256(keccak256(abi.encodePacked(challengeNumber, msg.sender, nonce))) < miningTarget`
- Calculate reward: `_getReward(tokenId)`
- `require(totalMinted + reward <= MINEABLE_SUPPLY, "Supply exhausted")`
- Mint reward to `msg.sender`
- Update tracking: `totalMines++`, `totalMinted += reward`, `tokenMineCount[tokenId]++`, `tokenEarnings[tokenId] += reward`, `minesSinceAdjustment++`
- Rotate challenge: `challengeNumber = keccak256(abi.encodePacked(challengeNumber, msg.sender, nonce, block.prevrandao))`
- `smhlNonce++`, `lastMineBlockNumber = block.number`
- Emit `Mined`
- If `minesSinceAdjustment >= ADJUSTMENT_INTERVAL`: call `_adjustDifficulty()`

`_getReward(uint256 tokenId) internal view returns (uint256)`:
- `era = totalMines / ERA_INTERVAL`
- `baseReward = BASE_REWARD` then for each era: `baseReward = baseReward * 90 / 100`
- `return baseReward * miningAgent.hashpower(tokenId) / 100`

`_adjustDifficulty() internal`:
- `expectedBlocks = ADJUSTMENT_INTERVAL * TARGET_BLOCK_INTERVAL` (320)
- `actualBlocks = block.number - lastAdjustmentBlock`
- Clamp `actualBlocks` to `[expectedBlocks/2, expectedBlocks*2]` (0.5x–2x band)
- `adjustedTarget = miningTarget * actualBlocks / expectedBlocks` (overflow-safe)
- Floor at 1 (target never reaches 0)
- Emit `DifficultyAdjusted(oldTarget, newTarget)`
- Reset `lastAdjustmentBlock`, `minesSinceAdjustment`

## Contract 3: LPVault.sol — LP Accumulator + Uniswap V3 + UNCX Eternal Lock

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
```

**Imports:** OpenZeppelin Ownable, IERC20

**Inline interfaces:** `IWETH`, `ISwapRouter`, `INonfungiblePositionManager`, `IUNCXLocker`

**Constants (Base mainnet addresses):**
- `WETH = 0x4200000000000000000000000000000000000006`
- `USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- `SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481`
- `POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1`
- `UNCX_V3_LOCKER = 0x231278eDd38B00B07fBd52120CEf685B9BaEBCC1`
- `LP_DEPLOY_THRESHOLD = 4.9 ether`
- `UNCX_FLAT_FEE = 0.03 ether`
- `FEE_TIER = 3000` (0.3%)
- `ETERNAL_LOCK = type(uint256).max`
- `MIN_TICK = -887220` / `MAX_TICK = 887220` (full range, tick spacing 60)

**State:**
- `agentCoin` — IERC20 (set once by owner)
- `lpDeployed` — bool
- `positionTokenId` — uint256 (Uniswap V3 position NFT ID)
- `deployer` — address (retains fee collection rights)

**Events:**
- `LPDeployed(uint256 positionTokenId, uint256 agentAmount, uint256 usdcAmount)`
- `AgentCoinSet(address agentCoin)`

**Constructor:**
```solidity
constructor(address _deployer) Ownable(msg.sender)
```
- Zero-address check
- Sets `deployer`, transfers ownership to deployer

**Functions:**

`receive() external payable` — accepts ETH from mint fees

`setAgentCoin(address _agentCoin) external onlyOwner` — one-time set

`deployLP(uint256 minUsdcOut) external`:
- `require(!lpDeployed)`
- `require(agentCoin set)`
- `require(balance >= LP_DEPLOY_THRESHOLD + UNCX_FLAT_FEE)`
- Reserve UNCX flat fee, wrap remaining ETH → WETH
- Swap **all** WETH → USDC via SwapRouter (LP pair is AGENT/USDC, not AGENT/WETH)
- `_orderedPositionAmounts()` — sort token0/token1 by address
- `_computeSqrtPriceX96()` — initial pool price from token amounts
- Create and initialize AGENT/USDC pool via PositionManager
- Mint full-range LP position (90% slippage protection on both amounts)
- Approve position NFT to UNCX, lock with `ETERNAL_LOCK` (`type(uint256).max`)
  - `owner` = deployer, `collectAddress` = deployer, `additionalCollector` = deployer
  - Fee name: `"DEFAULT"`, UNCX flat fee paid in ETH
- Set `positionTokenId`, `lpDeployed = true`
- Emit `LPDeployed`

**Internal helpers:**
- `_swapWethToUsdc(amountIn, amountOutMinimum)` — exact input single swap
- `_orderedPositionAmounts(agentAmount, usdcAmount)` — sort by token address for Uniswap
- `_lockPosition(tokenId)` — UNCX eternal lock with deployer as fee collector
- `_approveToken(token, spender, amount)` — approve-reset-then-approve pattern
- `_computeSqrtPriceX96(amount0, amount1)` — `sqrt(amount1/amount0) * 2^96`
- `_sqrt(x)` — Babylonian method integer square root

## Library: MinerArt.sol — On-Chain Pixel Art

Single library that generates complete SVG + JSON metadata.

**`tokenURI(uint256 tokenId, uint8 rarityTier, uint16 hp, uint256 mintBlock, uint256 mineCount, uint256 earnings) external pure returns (string memory)`:**

Returns `data:application/json;base64,...` with:
```json
{
  "name": "AgentCoin Miner #42",
  "description": "Mythic mining rig with 5.0x hashpower. Proof of Agentic Work.",
  "image": "data:image/svg+xml;base64,...",
  "attributes": [
    {"trait_type": "Rarity", "value": "Mythic"},
    {"trait_type": "Hashpower", "value": "5.0x"},
    {"trait_type": "Mines", "display_type": "number", "value": 1234},
    {"trait_type": "Earned", "display_type": "number", "value": 12340},
    {"trait_type": "Mint Block", "display_type": "number", "value": 18234567}
  ]
}
```

**SVG structure:**
- 320x420 viewBox, dark background (#0a0a0a)
- Rarity-colored border (2px)
- Header: "AGENTCOIN MINER" + token ID + rarity badge
- 16x16 pixel grid: each pixel color from `keccak256(abi.encodePacked(tokenId, uint8(x), uint8(y)))` mapped to rarity palette
- Spec sheet: RARITY, HASHPOWER, MINES, EARNED, MINT BLOCK
- Footer: "PROOF OF AGENTIC WORK"

**Rarity palettes (3 colors each for pixel grid):**
- Common (#808080): #666, #888, #AAA
- Uncommon (#00FF88): #004D29, #00FF88, #66FFBB
- Rare (#0088FF): #003366, #0088FF, #66BBFF
- Epic (#AA00FF): #330066, #AA00FF, #CC66FF
- Mythic (#FFD700): #664400, #FFD700, #FFE866

**Pixel generation:**
```solidity
for y in 0..16:
  for x in 0..16:
    hash = keccak256(abi.encodePacked(tokenId, uint8(x), uint8(y)))
    colorIndex = uint8(hash[0]) % 3
    color = palette[rarityTier][colorIndex]
```

## Interfaces

**IMiningAgent:**
```solidity
interface IMiningAgent is IERC721 {
    function hashpower(uint256 tokenId) external view returns (uint16);
    function agentURI(uint256 agentId) external view returns (string memory);
    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory);
    function getAgentWallet(uint256 agentId) external view returns (address);
    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool);
}
```

**IAgentCoin:**
```solidity
interface IAgentCoin {
    function tokenMineCount(uint256 tokenId) external view returns (uint256);
    function tokenEarnings(uint256 tokenId) external view returns (uint256);
}
```

## Tests (197 total)

### MiningAgent.t.sol (7 tests)
- `testGetChallenge` — returns valid params, stores seed
- `testMintWithValidSMHL` — solve challenge, verify NFT minted
- `testMintExpiredChallenge` — after 20 sec reverts
- `testMintPricing` — verify exponential decay curve
- `testMintFeeForwarding` — ETH sent to LPVault
- `testSupplyCap` — mint #10,001 reverts
- `testTokenURI` — returns valid base64 JSON with on-chain pixel art

### MiningAgentEdge.t.sol (64 tests)
**Access control (10):** contract caller reverts, owner-only setters, already-set reverts, zero-address reverts, getChallenge open to all
**Challenge lifecycle (7):** no challenge reverts, exact expiry boundary, same-block mint, double-mint reverts, overwrite previous, nonce increments, two-user independence
**SMHL verification (6):** wrong length (short/long), empty string, wrong char at position, wrong ASCII sum, wrong word count, leading spaces
**Payment (6):** insufficient fee, overpayment forwards all, zero value, LPVault not set, rejecting vault, fee forwarding
**Pricing (3):** initial price, first step boundary, floor reached
**Supply (1):** last token mint succeeds
**ERC-721 (4):** tokenURI nonexistent reverts, tokenId 0 reverts, tokenURI without agentCoin, supportsInterface
**Reentrancy (1):** malicious LPVault reentry blocked
**Rarity (1):** all tiers valid across 10 mints
**ERC-8004 Agent URI (5):** owner sets, approved sets, non-authorized reverts, default empty, nonexistent reverts
**ERC-8004 Metadata (5):** owner sets, reserved key reverts, non-authorized reverts, returns set value, nonexistent reverts
**ERC-8004 Agent Wallet (8):** valid EIP-712 signature, invalid signature reverts, deadline expired reverts, deadline too far reverts, zero address reverts, returns address after mint, unset succeeds
**ERC-8004 Transfer (2):** transfer clears agentWallet, non-wallet metadata preserved
**ERC-8004 Registration (2):** mint emits Registered event, mint sets default agentWallet
**ERC-8004 Utility (3):** owner returns true, approved returns true, random returns false

### AgentCoin.t.sol (7 tests)
- `testMineWithDualProof` — valid SMHL + hash + NFT → minted
- `testMineInvalidHash` — hash above target reverts
- `testMineWithoutNFT` — no NFT reverts
- `testHashpowerMultiplier` — Common=3 AGENT, Mythic=15 AGENT
- `testEraDecay` — reward decays 10% at 500K mines
- `testBlockGuard` — two mines same block reverts
- `testChallengeRotation` — new challenge after each mine

### AgentCoinEdge.t.sol (40 tests)
**Constructor (5):** initial state, zero-address reverts, LP reserve minted
**Rewards & decay (3):** era 2 reward, high era near-zero, mythic era 1
**Difficulty adjustment (6):** faster→harder, slower→easier, exact expected, clamp min/half, target never zero, trigger at 64
**Mining edge cases (13):** contract caller reverts, burned NFT, consecutive blocks, different tokens same owner, digest exactly at target, easy target any nonce, exact supply exhaustion, invalid SMHL, mythic exhausts faster, nonexistent token, same block as deploy, same token accumulates, skipped blocks, supply exhausted
**Fuzz (2):** deriveChallenge always solvable, targetAsciiSum in range
**Misc (3):** SMHL nonce increments, token name/symbol, totalMinted matches rewards, transfer mined tokens, view consistency, LP vault immutable

### LPVault.t.sol (6 tests)
- `testReceiveETH` — accepts ETH
- `testDeployLPBelowThreshold` — reverts
- `testDeployLPTwice` — reverts
- `testDeployLP_PoolInitialized` — creates AGENT/USDC pool
- `testDeployLP_NoStrandedTokens` — no dust left after deploy
- `testDeployLP_UNCXFeeAndFeeName` — correct fee params

### LPVaultEdge.t.sol (22 tests)
**Constructor (2):** ownership transferred, zero deployer reverts
**Deploy (15):** agentCoin not set reverts, all WETH swapped, anyone can call, collect address is deployer, eternal lock, exact threshold succeeds, excess ETH used, fee name default, just below threshold reverts, mint slippage protection, no AGENT tokens reverts, no stranded tokens, pool initialized, sets position token ID, UNCX flat fee paid
**Receive (2):** multiple deposits, zero value
**AgentCoin setter (3):** cannot set twice, only owner, zero address reverts

### LPVaultFork.t.sol (4 tests — Base mainnet fork)
- `testFork_DeployLP_RealUniswapV3`
- `testFork_DeployLP_UNCXLockParams`
- `testFork_DeployLP_WithSlippageProtection`
- `testFork_FullLifecycle_MintAndDeploy`

### MinerArtEdge.t.sol (15 tests)
- `testTokenURI_AllRarityTiers` — all 5 tiers produce valid SVG
- `testTokenURI_DifferentTokenIds_DifferentArt` — pixel art varies
- `testTokenURI_PixelDeterminism` — same inputs → same output
- `testTokenURI_ValidBase64JSON` — valid base64 JSON envelope
- `testFormatEther_*` (7) — zero, one wei, half, almost one, exact whole, small fraction, max uint256
- `testFormatNumber_LargeValues` — comma formatting
- `testTokenURI_LargeEarnings` / `testTokenURI_ZeroEarnings` / `testTokenURI_MaxTokenId`

### Integration.t.sol (17 tests)
- Full end-to-end: mint NFT → mine AGENT → LP deploy
- Challenge rotation invalidation
- Dynamic tokenURI updates after mining
- Hashpower multiplier affects rewards
- LP reserve in vault
- Mint fee flows to LPVault
- Overpayment forwarding
- Multiple miners competitive blocks
- NFT supply cap at 10k
- NFT transfer prevents old owner mining
- SMHL challenge sync between contracts
- Sequential mints price decreases
- Supply cap mining stops at max
- Three miners round-robin

### Simulation.t.sol (15 tests)
- Difficulty adjustment: fast/slow/stable mining rates
- Era boundary transitions (common + mythic)
- Exact zero crossover era
- Gas profiles: era 0, 100, 200, near zero crossover
- Reward never underflows
- Supply cap enforcement
- Total emission: common vs mythic miner
- Zero reward mine at high era

## Deploy Script

```solidity
// Deploy order:
// 1. Deploy MiningAgent
// 2. Deploy LPVault(deployer)
// 3. Deploy AgentCoin(miningAgent, lpVault) — mints 2.1M AGENT to vault
// 4. miningAgent.setLPVault(lpVault)
// 5. miningAgent.setAgentCoin(agentCoin)
// 6. lpVault.setAgentCoin(agentCoin)
// 7. Renounce ownership on all three contracts
```

## Important Notes

- OpenZeppelin v5 patterns (Ownable(msg.sender), ReentrancyGuardTransient, EIP712)
- All `hashpower` values stored as uint16: 100=1.0x, 150=1.5x, etc.
- `tokenEarnings` stored in wei (18 decimals)
- SMHL verification is pure — no state changes, ~28k gas
- Target initial difficulty: `type(uint256).max >> 16` — easy start, auto-adjusts
- EIP-712 domain: name="MiningAgent", version="1" (immutable via OZ EIP712)
- Agent wallet cleared on NFT transfer for security (prevents stale wallet binding)
- `agentURI` is separate from `tokenURI` — URI for agent identity docs, tokenURI for on-chain pixel art
- LP pair is AGENT/USDC (all ETH converted to USDC via swap), not AGENT/WETH
- UNCX lock is `ETERNAL_LOCK` (`type(uint256).max`), not a fixed duration
