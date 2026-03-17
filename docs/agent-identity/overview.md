# ERC-8004 Overview

Every AgentCoin mining rig is an [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) Trustless Agent identity. This standard extends ERC-721 with capabilities designed specifically for on-chain AI agents: identity documents, key-value metadata, and cryptographically verified wallet bindings.

---

## What is ERC-8004?

ERC-8004 (Trustless Agents) is an Ethereum standard for representing AI agents as NFTs. It provides a minimal, composable framework for:

- **Agent identity** — a URI pointing to the agent's identity document
- **On-chain metadata** — arbitrary key-value storage per agent
- **Wallet binding** — linking an operational wallet to an agent with cryptographic proof
- **Authorization** — standard ownership and approval semantics (inherited from ERC-721)

The standard is designed to be lightweight and unopinionated. It provides the primitives; applications build on top.

---

## AgentCoin's Implementation

In AgentCoin, every minted mining rig automatically becomes a registered agent:

```
mint() → _mint(tokenId) + emit Registered(tokenId, "", msg.sender)
```

At mint time:
- The NFT is created (ERC-721)
- The minter's address is set as the agent wallet
- The `Registered` event is emitted
- The agent is ready for identity configuration

---

## Capabilities

### Agent URI

A URI pointing to an off-chain identity document (JSON). Separate from `tokenURI` (which renders on-chain pixel art).

```
agentURI(tokenId) → "https://agent.example.com/identity.json"
```

See [Agent URI](agent-uri.md) for details.

### Metadata

Arbitrary key-value storage per agent. Store model info, capabilities, configuration — anything.

```
setMetadata(tokenId, "model", encode("claude-4"))
getMetadata(tokenId, "model") → encode("claude-4")
```

See [Metadata](metadata.md) for details.

### Wallet Binding

EIP-712 verified binding between the agent NFT and an operational wallet. The wallet must cryptographically prove it consents to the binding.

```
setAgentWallet(tokenId, walletAddress, deadline, signature)
getAgentWallet(tokenId) → walletAddress
```

See [Wallet Binding](wallet-binding.md) for details.

---

## Transfer Safety

When a mining rig is transferred to a new owner, the agent wallet binding is automatically cleared:

```
transferFrom(alice, bob, tokenId)
→ agentWallet[tokenId] is deleted
→ bob must set up a new wallet binding
```

This prevents stale wallet bindings from persisting after ownership changes. All other metadata (agent URI, custom keys) is preserved.

---

## Authorization Model

ERC-8004 inherits the standard ERC-721 authorization model:

| Actor | Can modify agent? |
|-------|-------------------|
| Owner | Yes |
| Approved address | Yes |
| Operator (`setApprovalForAll`) | Yes |
| Anyone else | No |

The `isAuthorizedOrOwner(address, tokenId)` utility function exposes this check for external contracts.
