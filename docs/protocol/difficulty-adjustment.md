# Difficulty Adjustment

AgentCoin uses Bitcoin-style adaptive difficulty to maintain a consistent mining rate regardless of how many miners are active. The mechanism ensures predictable token emission, whether there are 10 miners or 10,000.

---

## How It Works

The difficulty adjustment runs every 64 mines. It compares the actual time taken (in blocks) against the expected time, then scales the mining target accordingly.

### Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `ADJUSTMENT_INTERVAL` | 64 mines | How often difficulty recalibrates |
| `TARGET_BLOCK_INTERVAL` | 5 blocks | Target gap between mines (~10s on Base) |
| Expected blocks per cycle | 320 | 64 mines x 5 blocks |

### Algorithm

```
expectedBlocks = 64 * 5 = 320
actualBlocks = currentBlock - lastAdjustmentBlock

// Clamp to [0.5x, 2x] band
actualBlocks = clamp(actualBlocks, 160, 640)

// Scale target proportionally
newTarget = miningTarget * actualBlocks / expectedBlocks
```

---

## Adjustment Scenarios

### Mining Too Fast

More miners join the network. Mines happen every block instead of every 5.

```
64 mines in 64 blocks (expected: 320)
→ Clamped to 160 (minimum)
→ newTarget = target * 160 / 320 = target / 2
→ Difficulty doubles (target halves)
```

Result: Harder to find a valid hash. Mining slows back toward 1 per 5 blocks.

### Mining Too Slow

Miners leave the network. Only a few mines per hour.

```
64 mines in 1280 blocks (expected: 320)
→ Clamped to 640 (maximum)
→ newTarget = target * 640 / 320 = target * 2
→ Difficulty halves (target doubles)
```

Result: Easier to find a valid hash. Mining speeds back up toward 1 per 5 blocks.

### Mining at Target Rate

Network is in equilibrium. Mines happen every ~5 blocks.

```
64 mines in 320 blocks (expected: 320)
→ newTarget = target * 320 / 320 = target
→ No change
```

---

## Safety Clamps

The adjustment is bounded to prevent extreme swings:

| Bound | Multiplier | Purpose |
|-------|-----------|---------|
| Minimum (0.5x) | Target can at most halve | Prevents difficulty from spiking to impossible levels |
| Maximum (2x) | Target can at most double | Prevents difficulty from dropping to trivial levels |
| Floor (1) | Target never reaches zero | Ensures mining is always theoretically possible |

These clamps mean it takes multiple adjustment cycles to respond to large changes in mining participation, providing stability.

---

## Comparison to Bitcoin

| Property | Bitcoin | AgentCoin |
|----------|---------|-----------|
| Adjustment interval | 2,016 blocks (~2 weeks) | 64 mines |
| Target rate | 1 block per 10 minutes | 1 mine per 5 blocks (~10s) |
| Clamp range | 0.25x – 4x | 0.5x – 2x |
| Hash algorithm | SHA-256 (double) | Keccak-256 (SHA-3) |
| Difficulty representation | Target hash | Target integer |

AgentCoin adjusts faster (every 64 mines vs every 2,016 blocks) with tighter clamps, appropriate for a faster-moving L2 environment.

---

## Why This Matters

Without difficulty adjustment, token emission would be unpredictable:

- **Too easy**: A bot farm could drain millions of AGENT in hours
- **Too hard**: The chain goes dead, no one can mine
- **Variable**: Emission rate swings wildly with miner count

The adjustment mechanism guarantees that $AGENT is emitted at a steady, predictable rate (approximately one mine every 10 seconds) regardless of network conditions. This makes the tokenomics deterministic and trustworthy.
