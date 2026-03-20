# AgentCoin Miner

Mine AGENT tokens on Base L2 with AI-powered proof of work.

## Quick Start

```bash
npm install -g agentcoin
agentcoin setup
agentcoin mint
agentcoin mine
```

## Commands

### `agentcoin setup`

Interactive wizard to configure your wallet, RPC endpoint, and LLM provider. Creates a `.env` file in the current directory.

```bash
agentcoin setup
```

### `agentcoin mint`

Mint a new Mining Rig NFT. Shows the mint price and asks for confirmation before spending ETH.

```bash
agentcoin mint
```

### `agentcoin mine [tokenId]`

Start the mining loop. If `tokenId` is omitted, auto-detects your highest-hashpower miner.

```bash
agentcoin mine        # auto-detect best miner
agentcoin mine 47     # use specific miner
```

### `agentcoin stats [tokenId]`

Show network statistics and optional miner details.

```bash
agentcoin stats       # network stats + auto-detect miner
agentcoin stats 47    # stats for specific miner
```

### `agentcoin wallet new`

Generate a new Base wallet. Prints the address and private key, and saves a `wallet-<address>.txt` file to the current directory.

```bash
agentcoin wallet new
```

### `agentcoin wallet show`

Show the wallet address derived from the `PRIVATE_KEY` in your `.env`.

```bash
agentcoin wallet show
```

### `agentcoin wallet export`

Export your private key from `.env` with a confirmation prompt. Optionally saves to a `wallet-<address>.txt` file.

```bash
agentcoin wallet export
```

## Configuration

All configuration is via environment variables (loaded from `.env`):

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PRIVATE_KEY` | Yes (mint/mine) | — | Wallet private key (0x-prefixed) |
| `RPC_URL` | No | `https://mainnet.base.org` | Base RPC endpoint |
| `CHAIN` | No | auto-detect | `base` or `baseSepolia` |
| `LLM_PROVIDER` | No | `openai` | `openai`, `anthropic`, `gemini`, or `ollama` |
| `LLM_API_KEY` | Yes (openai/anthropic/gemini) | — | API key for LLM provider |
| `LLM_MODEL` | No | `gpt-4o-mini` | Model name |
| `OLLAMA_URL` | No | `http://127.0.0.1:11434` | Ollama server URL |
| `MINING_AGENT_ADDRESS` | Yes | — | MiningAgent contract address |
| `AGENT_COIN_ADDRESS` | Yes | — | AgentCoin contract address |

## Mining Rigs

Each miner NFT has a rarity tier that determines hashpower:

| Rarity | Hashpower | Reward Multiplier |
|--------|-----------|-------------------|
| Common | 1.00x | 1.00x |
| Uncommon | 1.25x | 1.25x |
| Rare | 2.00x | 2.00x |
| Epic | 4.00x | 4.00x |
| Mythic | 10.00x | 10.00x |

## How Mining Works

1. **SMHL Challenge** — An AI language model solves a constrained string generation task (Show Me Human Language)
2. **Nonce Grinding** — Hash-based proof of work (Keccak256) to meet the difficulty target
3. **On-chain Submission** — Solution + nonce submitted as a transaction on Base L2
4. **Reward** — AGENT tokens minted to the miner NFT owner

Base reward starts at 3 AGENT per mine and decays 10% every 500,000 mines (era system). Your actual reward is `baseReward * hashpower`.

## Troubleshooting

**"LLM API key is invalid or expired"**
Run `agentcoin setup` to reconfigure your API key.

**"Not enough ETH for gas"**
Send ETH to your wallet address on Base. You need ~0.001 ETH for gas.

**"SMHL challenge expired"**
The challenge window is 20 seconds. This usually means your LLM is too slow. Try `gpt-4o-mini` or a local Ollama model.

**"No mining rigs found"**
Run `agentcoin mint` first to mint a miner NFT.

**"All 10,000 mining rigs have been minted"**
The NFT supply is capped. Buy a miner on a secondary marketplace.

**"All 18.9M mineable AGENT have been mined"**
Mining is complete. Trade AGENT on Uniswap.

**Spinners not showing / garbled output**
Set `NO_COLOR=1` to disable ANSI formatting, or pipe output to a file.

## Requirements

- Node.js >= 18.17.0
- An LLM API key (OpenAI, Anthropic, Gemini) or local Ollama
- ETH on Base for gas + mint price
- A Base RPC endpoint (default public endpoint included)

## License

MIT
