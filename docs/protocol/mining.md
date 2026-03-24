# Mining

Mining $AGENT requires owning an ERC-721 Mining Rig (which proves AI capability at mint time) and submitting dual proof-of-work: an SMHL format proof plus a traditional SHA-3 hash proof. The real competitive mechanism is hash power; SMHL serves as lightweight format verification during mining, while NFT ownership is the meaningful gate.

> **RPC Endpoint Required:** The default public Base RPC (`mainnet.base.org`) is unreliable for sustained mining. We strongly recommend a free dedicated endpoint from [Alchemy](https://www.alchemy.com/) or [QuickNode](https://www.quicknode.com/), no credit card needed. See [RPC Scalability](../technical/rpc-scalability.md) for setup instructions.

---

## Dual Proof System

Every mine requires two proofs submitted in a single transaction:

### 1. SMHL (Show Me Human Language)

A format verification challenge derived from on-chain entropy. The contract checks three constraints with generous tolerances:

**Verified constraints (on-chain):**

| Constraint | Tolerance | Description |
|-----------|-----------|-------------|
| `totalLength` | ±5 chars | Approximate string length |
| `wordCount` | ±2 words | Approximate space-separated word count |
| `charValue` | exact | A lowercase letter (a–z) that must appear anywhere in the string |

**Derived but not verified:** `targetAsciiSum`, `firstNChars`, `charPosition`. These fields exist in the challenge struct for future extensibility but are not checked by `_verifySMHL()`.

**Role in mining vs minting:**
- **Minting:** SMHL serves as AI verification. The LLM must solve the challenge within 20 seconds to prove AI capability. This is the "prove yourself" gate.
- **Mining:** SMHL is lightweight format verification. The mining CLI solves it algorithmically in microseconds. The real competitive mechanism is the SHA-3 hash proof below. AI was already proven when you minted your Mining Rig.

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

2. Off-chain: generate SMHL solution
   └── Algorithmic, satisfies format constraints in microseconds

3. Off-chain: find a valid nonce (the competitive part)
   └── Multi-threaded: Hash(challengeNumber + address + nonce) < miningTarget

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
