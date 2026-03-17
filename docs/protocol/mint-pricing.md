# Mint Pricing

Mining rig pricing follows an exponential decay curve. Early minters pay a premium; late minters get rigs at the floor price. All mint revenue funds protocol-owned liquidity.

---

## Pricing Parameters

| Parameter | Value |
|-----------|-------|
| Starting price | 0.002 ETH |
| Floor price | 0.0002 ETH |
| Step size | Every 100 mints |
| Decay rate | 5% per step |
| Decay formula | `price = 0.002 * (0.95)^step` |

---

## Price Curve

| Mints | Price (ETH) | Phase |
|-------|-------------|-------|
| 0 | 0.002000 | Premium |
| 100 | 0.001900 | Premium |
| 500 | 0.001539 | Premium |
| 1,000 | 0.001184 | Premium |
| 2,000 | 0.000701 | Premium |
| 3,000 | 0.000415 | Premium |
| 4,500 | 0.000200 | Floor reached |
| 5,000 | 0.000200 | Distribution |
| 7,500 | 0.000200 | Distribution |
| 10,000 | 0.000200 | Distribution |

---

## Two Phases

### Premium Phase (Mints 0–4,500)

The first ~4,500 mints follow the decay curve from 0.002 ETH down to the 0.0002 ETH floor. Early supporters pay more but gain:

- **Time advantage** — earlier mining means more total AGENT earned over the rig's lifetime
- **First-mover position** — mine when competition is lowest and difficulty is easiest

### Distribution Phase (Mints 4,500–10,000)

The remaining ~5,500 mints are all at the 0.0002 ETH floor. This is the mass distribution phase:

- **Maximum accessibility** — anyone can afford a rig
- **Broad distribution** — more unique miners strengthens the network
- **Better ROI per ETH** — cheaper entry, same mining capability

---

## Revenue Allocation

100% of mint revenue flows to the LPVault contract in the same transaction. There is no team cut, no treasury allocation, no middleman.

```
Minter → MiningAgent.mint() → LPVault.receive()
```

### Estimated Total Revenue

```
Premium phase (~4,500 mints):  ~4.2 ETH
Distribution phase (~5,500 mints): ~1.1 ETH
                                   ─────────
Total:                             ~5.3 ETH
```

This ETH is converted to USDC and paired with the 2.1M AGENT LP reserve to create permanently locked Uniswap V3 liquidity.

---

## Why Exponential Decay

| Alternative | Problem |
|-------------|---------|
| Fixed price | No incentive to mint early |
| Linear decay | Price drops too fast initially, too slow later |
| Dutch auction | Creates sniping incentives and gas wars |
| Bonding curve (up) | Punishes late participants |

Exponential decay with a 5% step is gentle enough that there's no meaningful incentive to snipe — waiting 100 mints saves less than 0.0001 ETH. It rewards early supporters without punishing late participants, and the floor ensures mass distribution.
