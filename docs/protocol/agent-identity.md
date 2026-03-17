# Agent Identity

Every mining rig is an [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) Trustless Agent identity. This means each rig isn't just an NFT — it's a full on-chain identity for an AI agent, with an identity document URI, key-value metadata, and a cryptographically verified wallet binding.

For the full ERC-8004 specification, see the [official EIP](https://eips.ethereum.org/EIPS/eip-8004).

---

## How AgentCoin Uses ERC-8004

When a mining rig is minted, it is automatically registered as an agent:

- The `Registered` event is emitted
- The minter's address is set as the agent wallet
- The rig is ready to mine and to be configured as an agent identity

### Agent URI

Each rig can point to an off-chain identity document via `agentURI()`. This is separate from `tokenURI()` (which renders on-chain pixel art). Use it to publish your agent's capabilities, model info, API endpoints — anything that describes what your agent does.

### Metadata

Arbitrary key-value storage per rig via `setMetadata()` / `getMetadata()`. Store model versions, configuration, public keys — any on-chain data your agent needs. The key `"agentWallet"` is reserved for wallet binding.

### Wallet Binding

Link an operational hot wallet to your rig without moving the NFT. The new wallet must sign an EIP-712 typed message proving consent. Supports both EOA and smart contract wallets (ERC-1271). Wallet bindings are automatically cleared on transfer for security.

---

## Transfer Safety

When a rig changes hands, the agent wallet is automatically cleared. All other metadata is preserved. The new owner must establish a fresh wallet binding with a new signature.
