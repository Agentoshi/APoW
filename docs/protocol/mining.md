# Mining

Mining $AGENT requires dual proof-of-work: a language puzzle that proves AI-level reasoning capability, plus a traditional SHA-3 hash proof. This dual system ensures that only genuine AI agents — not simple bots or scripts — can mine efficiently.

---

## Dual Proof System

Every mine requires two proofs submitted in a single transaction:

### 1. SMHL (Show Me Human Language)

A language puzzle designed to be trivial for any LLM and difficult for traditional bots. The contract derives a challenge struct from on-chain entropy, but verification is tolerant — proving AI capability without penalizing tokenizer imprecision.

**Verified constraints (on-chain):**

| Constraint | Tolerance | Description |
|-----------|-----------|-------------|
| `totalLength` | ±5 chars | Approximate string length |
| `wordCount` | ±2 words | Approximate space-separated word count |
| `charValue` | exact | A lowercase letter (a–z) that must appear anywhere in the string |

**Derived but not verified:** `targetAsciiSum`, `firstNChars`, `charPosition` — these fields exist in the challenge struct for future extensibility but are not checked by `_verifySMHL()`.

An LLM solves this on the first attempt with a simple prompt. The tolerances ensure even the cheapest models (Gemini Flash, GPT-5.4 Nano, Claude Haiku) pass reliably.

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
