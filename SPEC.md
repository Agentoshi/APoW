# AgentCoin ($AGENT) — Implementation Spec

## Overview

Mineable ERC-20 on Base powered by Proof of Agentic Work (PoAW). Three contracts + one library.

## Contract 1: MiningAgent.sol — ERC-721 Mining Rig NFT

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
```

**Imports:** OpenZeppelin ERC721Enumerable, Ownable, Base64, Strings

**State:**
- `MAX_SUPPLY = 100_000`
- `MAX_PRICE = 0.001 ether` (first mint)
- `MIN_PRICE = 0.00005 ether` (floor)
- `CHALLENGE_DURATION = 20` (seconds)
- `lpVault` — address payable, set by owner
- `agentCoin` — address, set by owner (for dynamic NFT stats)
- `challengeNonce` — uint256, increments per mint
- `nextTokenId` — uint256, starts at 1

**Per-token storage:**
- `mapping(uint256 => uint8) public hashpower` — 100=1x, 150=1.5x, 200=2x, 300=3x, 500=5x
- `mapping(uint256 => uint8) public rarity` — 0=Common, 1=Uncommon, 2=Rare, 3=Epic, 4=Mythic
- `mapping(uint256 => uint256) public mintBlock` — block number at mint

**Challenge storage:**
- `mapping(address => bytes32) public challengeSeeds` — seed per address
- `mapping(address => uint256) public challengeTimestamps` — when challenge was requested

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

**Functions:**

`getChallenge(address minter) external returns (SMHLChallenge memory)`:
- Stores `challengeSeeds[minter] = keccak256(abi.encodePacked(minter, block.prevrandao, challengeNonce++))`
- Stores `challengeTimestamps[minter] = block.timestamp`
- Derives challenge params deterministically from seed:
  - `firstNChars = 5 + (seed[0] % 6)` → range 5-10
  - `targetAsciiSum = 400 + (uint16(seed[1]) * 3)` → range 400-1165 (adjusted to be feasible)
  - `wordCount = 3 + (seed[2] % 5)` → range 3-7
  - `charPosition = seed[3] % totalLength` (use a reasonable range, e.g., mod 20)
  - `charValue = 97 + (seed[4] % 26)` → lowercase a-z (97-122)
  - `totalLength = 20 + (seed[5] % 31)` → range 20-50
- Returns the challenge

`mint(string calldata solution) external payable`:
- `require(msg.sender == tx.origin, "No contracts")`
- `require(nextTokenId <= MAX_SUPPLY, "Sold out")`
- `require(challengeTimestamps[msg.sender] > 0, "No challenge")`
- `require(block.timestamp <= challengeTimestamps[msg.sender] + CHALLENGE_DURATION, "Expired")`
- `require(msg.value >= getMintPrice(), "Insufficient fee")`
- Reconstruct challenge from `challengeSeeds[msg.sender]`
- Verify SMHL: `_verifySMHL(solution, challenge)`
- Clear challenge data
- Determine rarity from `keccak256(abi.encodePacked(block.prevrandao, msg.sender, nextTokenId))`
- Mint NFT, set hashpower/rarity/mintBlock
- Forward ETH to `lpVault`

`_verifySMHL(string calldata solution, SMHLChallenge memory c) internal pure returns (bool)`:
- Check `bytes(solution).length == c.totalLength`
- Count words (spaces between non-space chars)
- Check word count == c.wordCount
- Check char at position == c.charValue
- Sum ASCII of first N chars, check == c.targetAsciiSum
- All checks must pass

`getMintPrice() public view returns (uint256)`:
- `remaining = MAX_SUPPLY - (nextTokenId - 1)`
- `price = MAX_PRICE * remaining / MAX_SUPPLY`
- `return price < MIN_PRICE ? MIN_PRICE : price`

`_determineRarity(bytes32 seed) internal pure returns (uint8 rarityTier, uint8 hp)`:
- `roll = uint256(seed) % 100`
- `roll < 1` → Mythic (4), hp=500 (representing 5.0x as basis points /100)
- `roll < 5` → Epic (3), hp=300
- `roll < 15` → Rare (2), hp=200
- `roll < 40` → Uncommon (1), hp=150
- else → Common (0), hp=100

`tokenURI(uint256 tokenId) public view override returns (string memory)`:
- Delegates to MinerArt library (implemented separately)
- Needs to query AgentCoin for mine count and earnings per token

`setAgentCoin(address _agentCoin) external onlyOwner`
`setLPVault(address payable _lpVault) external onlyOwner`

## Contract 2: AgentCoin.sol — ERC-20 + PoAW Mining

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
```

**Imports:** OpenZeppelin ERC20, Ownable

**Constants:**
- `MAX_SUPPLY = 21_000_000e18`
- `LP_RESERVE = 2_100_000e18` (10%)
- `MINEABLE_SUPPLY = 18_900_000e18` (90%)
- `BASE_REWARD = 3e18` (3 AGENT)
- `ERA_INTERVAL = 500_000` (mines per era, ~2 months at target rate)
- `REWARD_DECAY_NUM = 90` (10% decay per era)
- `REWARD_DECAY_DEN = 100`
- `ADJUSTMENT_INTERVAL = 64` (mines between difficulty adjustments)
- `TARGET_BLOCK_INTERVAL = 5` (target: 1 mine per 5 Base blocks = 10 sec)
- `CHALLENGE_DURATION = 20` (seconds for SMHL)

**State:**
- `miningAgent` — IMiningAgent interface reference
- `lpVault` — address
- `totalMines` — uint256
- `challengeNumber` — bytes32 (rotates each mine)
- `miningTarget` — uint256 (difficulty — hash must be below this)
- `lastMineBlockNumber` — uint256
- `lastAdjustmentBlock` — uint256
- `minesSinceAdjustment` — uint256
- `totalMinted` — uint256 (tracks minted supply)

**Per-token tracking (for dynamic NFT):**
- `mapping(uint256 => uint256) public tokenMineCount`
- `mapping(uint256 => uint256) public tokenEarnings`

**SMHL challenge for mining (separate from NFT mint SMHL):**
- `smhlNonce` — uint256 (increments each mine)
- Same `SMHLChallenge` struct as MiningAgent
- Challenge derived from `keccak256(challengeNumber, smhlNonce)`

**Functions:**

`constructor(address _miningAgent, address _lpVault)`:
- Mint `LP_RESERVE` to `_lpVault`
- Set initial `challengeNumber = keccak256("AgentCoin Genesis")`
- Set initial `miningTarget` to a reasonable starting difficulty
- Set `lastMineBlockNumber = block.number`
- Set `lastAdjustmentBlock = block.number`

`getMiningChallenge() external view returns (bytes32 challenge, uint256 target, SMHLChallenge memory smhl)`:
- Returns current `challengeNumber`, `miningTarget`, and current SMHL params
- SMHL derived from `keccak256(challengeNumber, smhlNonce)`

`mine(uint256 nonce, string calldata smhlSolution, uint256 tokenId) external`:
- `require(msg.sender == tx.origin, "No contracts")`
- `require(block.number > lastMineBlockNumber, "One mine per block")`
- `require(miningAgent.ownerOf(tokenId) == msg.sender, "Not your miner")`
- Verify SMHL solution against current challenge
- Verify hash: `keccak256(abi.encodePacked(challengeNumber, msg.sender, nonce)) < miningTarget`
- Calculate reward: `_getReward(tokenId)`
- `require(totalMinted + reward <= MAX_SUPPLY, "Supply exhausted")`
- Mint reward to `msg.sender`
- Update tracking: `totalMines++`, `tokenMineCount[tokenId]++`, `tokenEarnings[tokenId] += reward`, `totalMinted += reward`
- Rotate challenge: `challengeNumber = keccak256(abi.encodePacked(challengeNumber, msg.sender, nonce, block.prevrandao))`
- `smhlNonce++`
- `lastMineBlockNumber = block.number`
- Adjust difficulty if needed

`_getReward(uint256 tokenId) internal view returns (uint256)`:
- Determine era: `era = totalMines / ERA_INTERVAL`
- `baseReward = BASE_REWARD`, then for each era: `baseReward = baseReward * 90 / 100` (10% decay)
- `hp = miningAgent.hashpower(tokenId)` (100, 150, 200, 300, or 500)
- `return baseReward * hp / 100`

`_adjustDifficulty() internal`:
- Called every `ADJUSTMENT_INTERVAL` mines
- Measures actual blocks elapsed vs expected (ADJUSTMENT_INTERVAL * TARGET_BLOCK_INTERVAL)
- If too fast (fewer blocks than expected): decrease target (harder)
- If too slow (more blocks than expected): increase target (easier)
- Band: 0.5x to 2x adjustment per interval
- Updates `lastAdjustmentBlock` and resets `minesSinceAdjustment`

`setLPVault(address _lpVault) external onlyOwner`

## Contract 3: LPVault.sol — LP Accumulator + Uniswap V3 + UNCX

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
```

**Imports:** OpenZeppelin IERC20, Ownable, Uniswap V3 interfaces

**Constants (Base mainnet addresses):**
- `UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD`
- `SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481`
- `POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1`
- `WETH = 0x4200000000000000000000000000000000000006`
- `USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- `UNCX_V3_LOCKER = 0x231278eDd38B00B07fBd52120CEf685B9BaEBCC1`
- `LP_DEPLOY_THRESHOLD = 4.9 ether`
- `FEE_TIER = 3000` (0.3%)
- `LOCK_DURATION = 730 days` (2 years)

**State:**
- `agentCoin` — IERC20
- `lpDeployed` — bool
- `positionTokenId` — uint256 (Uniswap V3 NFT ID)
- `deployer` — address (retains fee collection rights)

**Functions:**

`constructor(address _deployer)`:
- Set deployer

`receive() external payable`:
- Accept ETH from mint fees

`setAgentCoin(address _agentCoin) external onlyOwner`:
- One-time set

`deployLP() external`:
- `require(!lpDeployed, "Already deployed")`
- `require(address(this).balance >= LP_DEPLOY_THRESHOLD, "Below threshold")`
- Wrap all ETH → WETH
- Swap half WETH → USDC via SwapRouter
- Approve AGENT + USDC to PositionManager
- Create position: `mint()` on NonfungiblePositionManager with full-range ticks
- Transfer position NFT to UNCX locker with 2-year lock, deployer as fee collector
- `lpDeployed = true`

`addLiquidity() external`:
- `require(lpDeployed, "LP not deployed")`
- `require(address(this).balance > 0, "No ETH")`
- Wrap ETH → WETH
- Swap half → USDC
- `increaseLiquidity()` on existing position
- Return dust

**Interfaces needed:**
- `ISwapRouter` (Uniswap V3)
- `INonfungiblePositionManager` (Uniswap V3)
- `IWETH` (WETH9)
- `IUNCXLocker` (UNCX V3 — check their interface)

## Library: MinerArt.sol — On-Chain SVG

Single library that generates complete SVG + JSON metadata.

**`tokenURI(uint256 tokenId, uint8 rarityTier, uint8 hp, uint256 mintBlock, uint256 mineCount, uint256 earnings) external pure returns (string memory)`:**

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

**SVG structure** (~18KB budget):
- 320x420 viewBox
- Dark background (#0a0a0a)
- Rarity-colored border (2px)
- Header: "AGENTCOIN MINER" + token ID + rarity badge
- 16x16 pixel grid: each pixel color from `keccak256(abi.encodePacked(tokenId, x, y))` mapped to rarity palette
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
    // append <rect x="..." y="..." width="12" height="12" fill="..." />
```

Use `abi.encodePacked()` for string building. Use OZ `Base64.encode()` and `Strings.toString()`.

## Tests

### MiningAgent.t.sol
- `testGetChallenge` — returns valid params, stores seed
- `testMintWithValidSMHL` — solve challenge, verify NFT minted
- `testMintInvalidSMHL` — wrong solution reverts
- `testMintExpiredChallenge` — after 20 sec reverts
- `testMintNoChallenge` — no prior getChallenge reverts
- `testMintPricing` — verify inverse bonding curve
- `testMintFeeForwarding` — ETH sent to LPVault
- `testRarityDistribution` — fuzz test, verify ~60/25/10/4/1 distribution
- `testSupplyCap` — mint #100,001 reverts
- `testNoContractMint` — contract caller reverts (tx.origin)

### AgentCoin.t.sol
- `testMineWithDualProof` — valid SMHL + hash + NFT → minted
- `testMineInvalidSMHL` — bad SMHL reverts
- `testMineInvalidHash` — hash above target reverts
- `testMineWithoutNFT` — no NFT reverts
- `testMineWrongNFTOwner` — not your NFT reverts
- `testHashpowerMultiplier` — Common=3, Mythic=15
- `testEraDecay` — reward decays 10% at 500K mines
- `testDifficultyAdjustment` — gets harder/easier
- `testBlockGuard` — two mines same block reverts
- `testSupplyCap` — mining stops at 21M
- `testChallengeRotation` — new challenge after each mine

### LPVault.t.sol
- `testReceiveETH` — accepts ETH
- `testDeployLP` — threshold check, creates position (fork test)
- `testDeployLPBelowThreshold` — reverts
- `testDeployLPTwice` — reverts
- `testAddLiquidity` — adds to existing position (fork test)

## Deploy Script — Deploy.s.sol

```solidity
// Deploy order:
// 1. Deploy MiningAgent
// 2. Deploy LPVault(deployer)
// 3. Deploy AgentCoin(miningAgent, lpVault) — this mints LP_RESERVE to vault
// 4. miningAgent.setLPVault(lpVault)
// 5. miningAgent.setAgentCoin(agentCoin)
// 6. lpVault.setAgentCoin(agentCoin)
```

## Important Notes

- Use OpenZeppelin v5 patterns (latest version in lib)
- All `hashpower` values are stored as uint8 basis: 100=1.0x, 150=1.5x, etc.
- `tokenEarnings` stored in wei (18 decimals)
- SMHL verification is pure — no state changes, ~28k gas
- Target initial difficulty: start easy so first mines succeed, then auto-adjust
- Use `Strings.toString()` for number→string in SVG
- Use `Base64.encode()` for base64 encoding
