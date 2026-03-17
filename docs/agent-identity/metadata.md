# Metadata

Every mining rig has an on-chain key-value metadata store. Owners can write arbitrary data to their agent's metadata, enabling composable agent identity without off-chain dependencies.

---

## Usage

### Writing

```solidity
setMetadata(uint256 agentId, string memory key, bytes memory value)
```

Only the owner or approved address can write metadata. The key `"agentWallet"` is reserved — use `setAgentWallet()` instead.

### Reading

```solidity
getMetadata(uint256 agentId, string memory key) → bytes memory
```

Anyone can read any agent's metadata. Returns empty bytes if the key is not set.

---

## Reserved Keys

| Key | Access | Description |
|-----|--------|-------------|
| `agentWallet` | `setAgentWallet()` only | EIP-712 verified wallet binding |

The `agentWallet` key cannot be set via `setMetadata()`. This is enforced by comparing the key's keccak256 hash against a stored constant. Attempting to use it reverts with `"Use setAgentWallet"`.

All other keys are unrestricted.

---

## Use Cases

### Model Information

```solidity
setMetadata(tokenId, "model", abi.encode("claude-4"))
setMetadata(tokenId, "modelVersion", abi.encode("2026-03"))
```

### Capabilities

```solidity
setMetadata(tokenId, "capabilities", abi.encode("trading,analysis,monitoring"))
```

### Configuration

```solidity
setMetadata(tokenId, "config", abi.encode(configJsonString))
```

### Inter-Agent Communication

```solidity
setMetadata(tokenId, "endpoint", abi.encode("https://agent.example.com/api"))
setMetadata(tokenId, "publicKey", abi.encodePacked(pubkey))
```

---

## Transfer Behavior

When a mining rig is transferred:

| Metadata Type | On Transfer |
|--------------|-------------|
| `agentWallet` | **Cleared** (security) |
| All other keys | **Preserved** |

This ensures wallet bindings don't persist through ownership changes, while agent configuration and identity data carries over.

---

## Events

Every metadata write emits:

```solidity
event MetadataSet(
    uint256 indexed agentId,
    string indexed indexedMetadataKey,
    string metadataKey,
    bytes metadataValue
)
```

The key is emitted both as an indexed topic (for efficient filtering) and as a regular parameter (for reading the actual value).

---

## Storage

Metadata is stored as a nested mapping:

```solidity
mapping(uint256 => mapping(string => bytes)) private _metadata
```

Each agent has its own key-value namespace. Keys are strings, values are raw bytes. Encoding and decoding is the caller's responsibility — use `abi.encode()` / `abi.decode()` for structured data, or `abi.encodePacked()` for compact representations.
