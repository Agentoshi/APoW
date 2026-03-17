#!/usr/bin/env node

import { Command } from "commander";

import { config } from "./config";
import { runMintFlow } from "./mint";
import { startMining } from "./miner";
import { displayStats } from "./stats";

function parseTokenId(value: string): bigint {
  try {
    return BigInt(value);
  } catch {
    throw new Error(`Invalid token ID: ${value}`);
  }
}

function printSetupInstructions(): void {
  console.log("Create a .env file with these values:");
  console.log("");
  console.log("PRIVATE_KEY=0xYOUR_PRIVATE_KEY");
  console.log(`RPC_URL=${config.rpcUrl}`);
  console.log("CHAIN=base");
  console.log(`LLM_PROVIDER=${config.llmProvider}`);
  console.log("LLM_API_KEY=your-provider-key");
  console.log(`LLM_MODEL=${config.llmModel}`);
  console.log("");
  console.log(`MiningAgent address placeholder: ${config.miningAgentAddress}`);
  console.log(`AgentCoin address placeholder: ${config.agentCoinAddress}`);
}

async function main(): Promise<void> {
  const program = new Command();

  program
    .name("agentcoin")
    .description("AgentCoin mining client")
    .version("0.1.0");

  program
    .command("setup")
    .description("Show the environment variables needed to configure the miner")
    .action(() => {
      printSetupInstructions();
    });

  program
    .command("mint")
    .description("Request a mint challenge, solve it, and mint a miner NFT")
    .action(async () => {
      await runMintFlow();
    });

  program
    .command("mine")
    .description("Start the mining loop with a miner NFT")
    .argument("<tokenId>", "Miner token ID")
    .action(async (tokenId: string) => {
      await startMining(parseTokenId(tokenId));
    });

  program
    .command("stats")
    .description("Show network stats and optional miner stats")
    .argument("[tokenId]", "Miner token ID")
    .action(async (tokenId?: string) => {
      await displayStats(tokenId ? parseTokenId(tokenId) : undefined);
    });

  await program.parseAsync(process.argv);
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exitCode = 1;
});
