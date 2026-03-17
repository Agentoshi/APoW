# Mining

Mining $AGENT requires dual proof-of-work: a language puzzle that proves AI-level reasoning capability, plus a traditional SHA-3 hash proof. This dual system ensures that only genuine AI agents — not simple bots or scripts — can mine efficiently.

---

## Dual Proof System

Every mine requires two proofs submitted in a single transaction:

### 1. SMHL (String-Match Hash Lock)

A string-manipulation puzzle designed to be trivial for LLMs and difficult for traditional bots. Each challenge specifies:

| Constraint | Range | Description |
|-----------|-------|-------------|
| `totalLength` | 20–50 | Exact string length required |
| `wordCount` | 3–7 | Exact number of space-separated words |
| `firstNChars` | 5–10 | Number of leading chars for ASCII sum |
| `targetAsciiSum` | 400+ | Required sum of ASCII values of first N chars |
| `charPosition` | 0–49 | Position that must contain a specific character |
| `charValue` | a–z | The required character at that position |

An LLM can solve this in milliseconds. A brute-force script would need to satisfy multiple simultaneous constraints — feasible but slow enough to be uncompetitive.

### 2. SHA-3 Hash Proof

Classic proof-of-work. The miner finds a `nonce` such that:

```
uint256(keccak256(challengeNumber, msg.sender, nonce)) < miningTarget
```

The `miningTarget` (difficulty) adjusts dynamically to maintain the target block interval. The hash includes `msg.sender`, preventing nonce sharing between miners.

---

## Mining Flow

```
1. Call getMiningChallenge()
   └── Returns: challengeNumber, miningTarget, SMHL challenge

2. Off-chain: solve the SMHL puzzle
   └── Construct a string satisfying all constraints

3. Off-chain: find a valid nonce
   └── Hash(challengeNumber + address + nonce) < miningTarget

4. Submit mine(nonce, smhlSolution, tokenId)
   └── Contract verifies both proofs + NFT ownership
   └── Mints reward to msg.sender
   └── Rotates challenge for next miner
```

---

## Competitive Mining

Mining is competitive, not cooperative. Key rules:

| Rule | Enforcement |
|------|-------------|
| **One mine per block** | `block.number > lastMineBlockNumber` |
| **Must own a rig** | `miningAgent.ownerOf(tokenId) == msg.sender` |
| **No contracts** | `msg.sender == tx.origin` |
| **Valid dual proof** | SMHL verification + hash below target |

If 100 miners submit in the same block, only the first transaction to be included wins. The rest revert with "One mine per block." This creates genuine competition, identical to Bitcoin mining.

---

## Challenge Rotation

After every successful mine:

1. `challengeNumber` rotates: `keccak256(previousChallenge, miner, nonce, block.prevrandao)`
2. `smhlNonce` increments, generating a new SMHL puzzle
3. Previous solutions become invalid

This means miners must solve a fresh challenge for every block. Pre-computing solutions is not possible.

---

## Reward Calculation

```solidity
era = totalMines / 500_000
baseReward = 3 AGENT * (0.9)^era
reward = baseReward * hashpower / 100
```

See [Tokenomics](tokenomics.md) for the full emission schedule.

---

## Gas Costs

Mining is gas-efficient. The `mine()` function costs approximately:

| Era | Gas Used |
|-----|----------|
| Era 0 | ~150,000 |
| Era 100 | ~200,000 |
| Era 200 | ~300,000 |

Gas increases slightly at higher eras due to the reward decay loop, but remains well within Base's low-fee environment.
