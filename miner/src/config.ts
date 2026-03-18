import { config as loadEnv } from "dotenv";
import type { Address, Chain, Hex } from "viem";
import { base, baseSepolia } from "viem/chains";

loadEnv();

export type LlmProvider = "openai" | "anthropic" | "ollama";
export type ChainName = "base" | "baseSepolia";

export interface AppConfig {
  privateKey?: Hex;
  rpcUrl: string;
  llmProvider: LlmProvider;
  llmApiKey?: string;
  llmModel: string;
  chain: Chain;
  chainName: ChainName;
  miningAgentAddress: Address;
  agentCoinAddress: Address;
}

const DEFAULT_RPC_URL = "https://mainnet.base.org";
const DEFAULT_LLM_PROVIDER: LlmProvider = "openai";
const DEFAULT_LLM_MODEL = "gpt-4o";
const DEFAULT_CHAIN_NAME: ChainName = "base";
// Set via MINING_AGENT_ADDRESS and AGENT_COIN_ADDRESS env vars after mainnet deployment
const DEFAULT_MINING_AGENT_ADDRESS = undefined;
const DEFAULT_AGENT_COIN_ADDRESS = undefined;

function normalizeProvider(value?: string): LlmProvider {
  if (value === "anthropic" || value === "ollama" || value === "openai") {
    return value;
  }

  return DEFAULT_LLM_PROVIDER;
}

function resolveChainName(): ChainName {
  const envChain = process.env.CHAIN;
  if (envChain === "base" || envChain === "baseSepolia") {
    return envChain;
  }

  const rpcUrl = process.env.RPC_URL ?? DEFAULT_RPC_URL;
  if (rpcUrl.toLowerCase().includes("sepolia")) {
    return "baseSepolia";
  }

  return DEFAULT_CHAIN_NAME;
}

function parsePrivateKey(value?: string): Hex | undefined {
  if (!value) {
    return undefined;
  }

  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) {
    throw new Error("PRIVATE_KEY must be a 32-byte hex string prefixed with 0x.");
  }

  return value as Hex;
}

function parseAddress(envKey: string, fallback: Address | undefined): Address {
  const value = process.env[envKey];
  if (value && /^0x[0-9a-fA-F]{40}$/.test(value)) {
    return value as Address;
  }
  if (fallback) {
    return fallback;
  }
  throw new Error(
    `${envKey} is required. Set it to the deployed contract address (0x-prefixed, 40 hex chars).`,
  );
}

const chainName = resolveChainName();

export const config: AppConfig = {
  privateKey: parsePrivateKey(process.env.PRIVATE_KEY),
  rpcUrl: process.env.RPC_URL ?? DEFAULT_RPC_URL,
  llmProvider: normalizeProvider(process.env.LLM_PROVIDER),
  llmApiKey: process.env.LLM_API_KEY,
  llmModel: process.env.LLM_MODEL ?? DEFAULT_LLM_MODEL,
  chain: chainName === "baseSepolia" ? baseSepolia : base,
  chainName,
  miningAgentAddress: parseAddress("MINING_AGENT_ADDRESS", DEFAULT_MINING_AGENT_ADDRESS),
  agentCoinAddress: parseAddress("AGENT_COIN_ADDRESS", DEFAULT_AGENT_COIN_ADDRESS),
};

export function requirePrivateKey(): Hex {
  if (!config.privateKey) {
    throw new Error("PRIVATE_KEY is required for minting and mining commands.");
  }

  return config.privateKey;
}

export function requireLlmApiKey(): string {
  if (config.llmProvider === "ollama") {
    return "";
  }

  if (!config.llmApiKey) {
    throw new Error(`LLM_API_KEY is required for ${config.llmProvider}.`);
  }

  return config.llmApiKey;
}
