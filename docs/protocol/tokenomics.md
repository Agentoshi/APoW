# Tokenomics

AgentCoin follows the Bitcoin model: fixed supply, predictable emission, decreasing rewards over time. No pre-mine. No team allocation. No VC tokens. The only way to get $AGENT is to mine it or buy it on the open market.

---

## Supply Distribution

| Allocation | Amount | Percentage | Purpose |
|-----------|--------|------------|---------|
| **Mineable Supply** | 18,900,000 AGENT | 90% | Earned through proof-of-work mining |
| **LP Reserve** | 2,100,000 AGENT | 10% | Permanently locked Uniswap V3 liquidity |
| **Total** | **21,000,000 AGENT** | **100%** | |

The LP reserve is minted to the LPVault contract at deployment. It is paired with USDC (converted from mint fee ETH) and locked forever via UNCX eternal lock. No one — not even the deployer — can access these tokens.

---

## Emission Schedule

Mining rewards follow an exponential decay curve across eras, similar to Bitcoin's halving schedule.

### Era System

| Parameter | Value |
|-----------|-------|
| Base reward | 3 AGENT per mine |
| Era interval | 500,000 mines |
| Decay rate | 10% per era |
| Decay formula | `reward = 3 * (0.9)^era` |

### Reward by Era

| Era | Total Mines | Reward per Mine | Cumulative Emission |
|-----|-------------|-----------------|---------------------|
| 0 | 0 – 499,999 | 3.000 AGENT | 1,500,000 |
| 1 | 500K – 999,999 | 2.700 AGENT | 2,850,000 |
| 2 | 1M – 1,499,999 | 2.430 AGENT | 4,065,000 |
| 3 | 1.5M – 1,999,999 | 2.187 AGENT | 5,158,500 |
| 4 | 2M – 2,499,999 | 1.968 AGENT | 6,142,650 |
| 5 | 2.5M – 2,999,999 | 1.771 AGENT | 7,028,385 |
| ... | ... | ... | ... |

The reward never increases. It asymptotically approaches zero, ensuring the 18.9M mineable cap is never exceeded.

---

## Hashpower Multiplier

Mining rewards are scaled by your rig's hashpower. A Mythic rig earns 5x more per mine than a Common rig:

```
actual_reward = base_reward * (hashpower / 100)
```

| Rarity | Hashpower | Reward at Era 0 |
|--------|-----------|-----------------|
| Common | 100 (1.0x) | 3.0 AGENT |
| Uncommon | 150 (1.5x) | 4.5 AGENT |
| Rare | 200 (2.0x) | 6.0 AGENT |
| Epic | 300 (3.0x) | 9.0 AGENT |
| Mythic | 500 (5.0x) | 15.0 AGENT |

Higher-rarity rigs don't mine more often — they earn more per mine when they win.

---

## Economic Dynamics

### For Miners

- **Early miners** earn higher rewards (earlier eras) but pay more for rigs
- **Late miners** pay less for rigs but earn lower rewards per mine
- **More miners** doesn't increase total emission — difficulty adjusts to maintain a constant rate
- **Hashpower matters** — Mythic rigs are genuinely 5x more productive than Common

### For the Market

- **Predictable emission** — the exact supply at any point in time is deterministic
- **Deflationary pressure** — rewards decrease every era while demand can grow
- **Permanent liquidity** — the LP is locked forever, providing a permanent trading floor
- **No sell pressure from team/VCs** — 100% of supply is either mined or locked in LP
