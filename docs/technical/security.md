# Security

AgentCoin is designed with defense-in-depth. Every contract follows the principle of least privilege, immutability by default, and fail-safe design.

---

## Immutability

After deployment and configuration, all admin functions are permanently disabled:

| Contract | Setter Functions | Post-Config |
|----------|-----------------|-------------|
| MiningAgent | `setAgentCoin`, `setLPVault` | One-time only, then reverts |
| AgentCoin | None | Immutable from deploy |
| LPVault | `setAgentCoin` | One-time only, then reverts |

Once the deployer calls `renounceOwnership()` on MiningAgent and LPVault, no further configuration changes are possible. AgentCoin has no owner functions at all.

---

## Liquidity Safety

| Protection | Mechanism |
|-----------|-----------|
| Eternal lock | UNCX `type(uint256).max`, LP can never be withdrawn |
| Atomic deployment | Wrap, swap, pool, liquidity, lock in one transaction |
| Slippage protection | 90% minimum on Uniswap V3 position mint |
| Owner-gated deployment | `deployLP()` is owner-gated and one-time |

---

## Mining Security

| Protection | Mechanism |
|-----------|-----------|
| No contracts | `msg.sender == tx.origin` on both `mint()` and `mine()` |
| One mine per block | `block.number > lastMineBlockNumber` |
| Challenge rotation | New challenge after every mine |
| SMHL verification | Pure function, ~28k gas, no state side effects |
| Hash includes sender | `keccak256(challenge, msg.sender, nonce)`, nonces aren't transferable |
| Reentrancy guard | `ReentrancyGuardTransient` (EIP-1153) on `mint()` and `mine()` |

---

## NFT Security

| Protection | Mechanism |
|-----------|-----------|
| SMHL identity gate | Minting requires LLM to solve SMHL within 20s, proving agent capability |
| 20-second window | Mint challenge expires quickly, preventing pre-computation |
| Challenge overwrite | New `getChallenge()` invalidates previous |
| Fee forwarding | Full `msg.value` sent to LPVault, nothing retained |

---

## Agent Identity Security

| Protection | Mechanism |
|-----------|-----------|
| Wallet consent | EIP-712 signature from the new wallet required |
| Deadline enforcement | 5-minute maximum, prevents replay |
| Transfer clear | `agentWallet` auto-deleted on NFT transfer |
| Reserved key | `"agentWallet"` blocked from `setMetadata()` |
| Smart wallet support | ERC-1271 verification for contract wallets |
| Domain binding | Chain ID + contract address in EIP-712 domain |

---

## Reentrancy Protection

Both MiningAgent and AgentCoin use `ReentrancyGuardTransient` from OpenZeppelin v5, which leverages EIP-1153 transient storage. This is more gas-efficient than traditional reentrancy guards and provides the same protection.

The LPVault's `deployLP()` is naturally protected by the `lpDeployed` flag, so it can only execute once.

---

## Known Considerations

### `tx.origin` Check

Both `mint()` and `mine()` require `msg.sender == tx.origin`. This prevents contract-based interaction but also means:

- Account abstraction (ERC-4337) wallets cannot directly mine or mint
- Users must interact from EOAs

This is an intentional design choice. The SMHL challenge system assumes a direct human/agent interaction pattern.

### Difficulty Floor

The mining target can never reach zero (floored at 1). In extreme scenarios where difficulty has increased to near-maximum, mining becomes very slow but never impossible.

### Era Decay Loop

The reward calculation loops through all past eras: `for (i = 0; i < era; i++) { reward = reward * 90 / 100 }`. At very high eras (300+), this loop becomes gas-intensive. However, at that point the reward rounds to zero, so mining would have naturally stopped.

---

## Audit Status

The contracts have been thoroughly tested with 231 tests covering:

- Unit tests for all public functions
- Edge cases for boundary conditions
- Integration tests for cross-contract interactions
- Simulation tests for long-term emission dynamics
- Fuzz tests for SMHL challenge solvability
- Gas profiling at various era levels
- Fork tests against Base mainnet infrastructure

All tests pass. The codebase is open source under MIT license.
