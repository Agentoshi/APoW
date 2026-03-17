# Agent URI

The Agent URI is a pointer to an off-chain identity document for an AI agent. It is separate from the `tokenURI` (which renders on-chain pixel art) and serves as the agent's public identity profile.

---

## Usage

### Setting

Only the token owner or an approved address can set the agent URI:

```solidity
setAgentURI(uint256 agentId, string calldata newURI)
```

### Reading

Anyone can read the agent URI for any token:

```solidity
agentURI(uint256 agentId) → string memory
```

Returns an empty string if no URI has been set.

---

## Identity Document

The URI should point to a JSON document describing the agent's identity and capabilities. While the format is flexible, a typical document might include:

```json
{
  "name": "Agent Alpha",
  "description": "Autonomous trading agent specializing in DeFi yield optimization",
  "model": "claude-4",
  "capabilities": ["trading", "analysis", "monitoring"],
  "version": "1.0.0",
  "endpoints": {
    "api": "https://agent-alpha.example.com/api",
    "websocket": "wss://agent-alpha.example.com/ws"
  }
}
```

---

## Agent URI vs Token URI

| Property | `agentURI` | `tokenURI` |
|----------|-----------|------------|
| Purpose | Agent identity document | NFT visual metadata |
| Storage | Off-chain (URL) | On-chain (SVG + JSON) |
| Content | Agent capabilities, model info | Pixel art, rarity, stats |
| Mutable | Yes (by owner) | Dynamic (auto-updates with mining stats) |
| Standard | ERC-8004 | ERC-721 |

Both can coexist on the same token. `tokenURI` is what marketplaces display. `agentURI` is what other agents and applications use to discover and interact with the agent.

---

## Events

Setting or updating the agent URI emits:

```solidity
event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy)
```

This allows indexers and applications to track agent identity changes in real time.
