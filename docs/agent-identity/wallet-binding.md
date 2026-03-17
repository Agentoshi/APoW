# Wallet Binding

Wallet binding links an AI agent's operational wallet to its on-chain identity. The binding is secured by EIP-712 typed signatures — the new wallet must cryptographically prove it consents to being associated with the agent.

---

## Why Wallet Binding?

An AI agent's NFT (the mining rig) is typically held in a cold wallet or multisig for security. But the agent needs a hot wallet to operate — sign transactions, interact with protocols, communicate with other agents.

Wallet binding creates a verified link between the agent identity (NFT) and its operational wallet, without exposing the NFT to the hot wallet's risk profile.

---

## Setting a Wallet

### Function

```solidity
setAgentWallet(
    uint256 agentId,
    address newWallet,
    uint256 deadline,
    bytes calldata signature
)
```

### Requirements

1. **Caller** must be the token owner or approved
2. **New wallet** must not be the zero address
3. **Deadline** must be in the future, but within 5 minutes
4. **Signature** must be a valid EIP-712 signature from `newWallet`

### EIP-712 Signature

The new wallet signs a typed message proving consent:

```
AgentWalletSet(
    uint256 agentId,
    address newWallet,
    address owner,
    uint256 deadline
)
```

Domain:
```
EIP712Domain(
    string name = "MiningAgent",
    string version = "1",
    uint256 chainId,
    address verifyingContract
)
```

This supports both EOA wallets (ECDSA) and smart contract wallets (ERC-1271).

---

## Reading the Wallet

```solidity
getAgentWallet(uint256 agentId) → address
```

Returns the bound wallet address, or `address(0)` if no wallet is bound.

---

## Unsetting the Wallet

```solidity
unsetAgentWallet(uint256 agentId)
```

Only the owner or approved address can unset. This deletes the wallet binding and emits a `MetadataSet` event with an empty value.

---

## Auto-Bind on Mint

When a mining rig is minted, `msg.sender` is automatically set as the agent wallet:

```solidity
_metadata[tokenId]["agentWallet"] = abi.encodePacked(msg.sender);
```

No signature is required at mint — the minter is implicitly consenting by minting.

---

## Transfer Safety

When a mining rig is transferred to a new owner, the wallet binding is **automatically cleared**:

```solidity
function _update(address to, uint256 tokenId, address auth) internal override {
    address from = super._update(to, tokenId, auth);
    if (from != address(0) && to != address(0)) {
        delete _metadata[tokenId]["agentWallet"];
    }
    return from;
}
```

This prevents a scenario where:
1. Alice binds her hot wallet to agent #42
2. Alice sells agent #42 to Bob
3. Alice's hot wallet is still bound to Bob's agent (security risk)

After transfer, Bob must set up a new wallet binding with a fresh EIP-712 signature.

---

## Deadline Window

The 5-minute maximum deadline prevents signature replay attacks. A wallet binding signature is only valid for a short window:

| Constraint | Value |
|-----------|-------|
| Minimum deadline | `block.timestamp` (current) |
| Maximum deadline | `block.timestamp + 5 minutes` |

Signatures with expired or too-distant deadlines are rejected.

---

## Security Properties

| Property | Guarantee |
|----------|-----------|
| **Mutual consent** | Both the NFT owner and the new wallet must agree |
| **Replay protection** | Deadline + chain ID + contract address |
| **Transfer safety** | Auto-cleared on ownership change |
| **Reserved key** | Cannot be set via generic `setMetadata()` |
| **Smart wallet support** | ERC-1271 signature verification |
