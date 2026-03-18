import type { Abi } from "viem";
import { encodePacked, formatEther, keccak256 } from "viem";

import agentCoinAbiJson from "./abi/AgentCoin.json";
import miningAgentAbiJson from "./abi/MiningAgent.json";
import { config } from "./config";
import { normalizeSmhlChallenge, solveSmhlChallenge } from "./smhl";
import { displayStats } from "./stats";
import { publicClient, requireWallet } from "./wallet";

const agentCoinAbi = agentCoinAbiJson as Abi;
const miningAgentAbi = miningAgentAbiJson as Abi;

const MAX_CONSECUTIVE_FAILURES = 10;
const BASE_BACKOFF_MS = 2_000;
const MAX_BACKOFF_MS = 60_000;

const BASE_REWARD = 3n * 10n ** 18n;
const REWARD_DECAY_NUM = 90n;
const REWARD_DECAY_DEN = 100n;

const FATAL_REVERTS = ["Not your miner", "Supply exhausted", "No contracts"];
const BLOCK_TOO_SOON_REVERTS = ["One mine per block"];

function elapsedSeconds(start: [number, number]): number {
  const [seconds, nanoseconds] = process.hrtime(start);
  return seconds + nanoseconds / 1_000_000_000;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function backoffMs(failures: number): number {
  const base = Math.min(BASE_BACKOFF_MS * 2 ** (failures - 1), MAX_BACKOFF_MS);
  const jitter = Math.random() * base * 0.3;
  return base + jitter;
}

function isFatalRevert(message: string): boolean {
  return FATAL_REVERTS.some((r) => message.includes(r));
}

function isBlockTooSoon(message: string): boolean {
  return BLOCK_TOO_SOON_REVERTS.some((r) => message.includes(r));
}

function estimateReward(totalMines: bigint, eraInterval: bigint, hashpower: bigint): bigint {
  const era = totalMines / eraInterval;
  let reward = BASE_REWARD;
  for (let i = 0n; i < era; i++) {
    reward = (reward * REWARD_DECAY_NUM) / REWARD_DECAY_DEN;
  }
  return (reward * hashpower) / 100n;
}

async function waitForNextBlock(lastMineBlock: bigint): Promise<void> {
  while (true) {
    const currentBlock = await publicClient.getBlockNumber();
    if (currentBlock > lastMineBlock) {
      return;
    }
    await sleep(500);
  }
}

async function grindNonce(
  challengeNumber: `0x${string}`,
  target: bigint,
  minerAddress: `0x${string}`,
): Promise<{ nonce: bigint; attempts: bigint; hashrate: number; elapsed: number }> {
  let nonce = 0n;
  let attempts = 0n;
  const start = process.hrtime();

  while (true) {
    const digest = BigInt(
      keccak256(
        encodePacked(["bytes32", "address", "uint256"], [challengeNumber, minerAddress, nonce]),
      ),
    );

    attempts += 1n;
    if (digest < target) {
      const elapsed = elapsedSeconds(start);
      const hashrate = elapsed > 0 ? Number(attempts) / elapsed : Number(attempts);
      return { nonce, attempts, hashrate, elapsed };
    }

    nonce += 1n;
  }
}

export async function startMining(tokenId: bigint): Promise<void> {
  const { account, walletClient } = requireWallet();
  let consecutiveFailures = 0;

  console.log(`Starting mining loop with token #${tokenId.toString()} on ${config.chain.name}.`);

  while (true) {
    try {
      // FIX 2: Pre-flight ownership check
      const owner = (await publicClient.readContract({
        address: config.miningAgentAddress,
        abi: miningAgentAbi,
        functionName: "ownerOf",
        args: [tokenId],
      })) as `0x${string}`;

      if (owner.toLowerCase() !== account.address.toLowerCase()) {
        console.error(`Token #${tokenId.toString()} is owned by ${owner}, not ${account.address}. Exiting.`);
        return;
      }

      // FIX 4: Supply exhaustion pre-check
      const [totalMines, totalMinted, mineableSupply, eraInterval, hashpower] = await Promise.all([
        publicClient.readContract({
          address: config.agentCoinAddress,
          abi: agentCoinAbi,
          functionName: "totalMines",
        }) as Promise<bigint>,
        publicClient.readContract({
          address: config.agentCoinAddress,
          abi: agentCoinAbi,
          functionName: "totalMinted",
        }) as Promise<bigint>,
        publicClient.readContract({
          address: config.agentCoinAddress,
          abi: agentCoinAbi,
          functionName: "MINEABLE_SUPPLY",
        }) as Promise<bigint>,
        publicClient.readContract({
          address: config.agentCoinAddress,
          abi: agentCoinAbi,
          functionName: "ERA_INTERVAL",
        }) as Promise<bigint>,
        publicClient.readContract({
          address: config.miningAgentAddress,
          abi: miningAgentAbi,
          functionName: "hashpower",
          args: [tokenId],
        }) as Promise<bigint>,
      ]);

      const estimatedReward = estimateReward(totalMines, eraInterval, hashpower);
      if (totalMinted + estimatedReward > mineableSupply) {
        console.log(
          `Supply nearly exhausted. Minted: ${formatEther(totalMinted)}, remaining: ${formatEther(mineableSupply - totalMinted)} AGENT. Exiting.`,
        );
        return;
      }

      const miningChallenge = (await publicClient.readContract({
        address: config.agentCoinAddress,
        abi: agentCoinAbi,
        functionName: "getMiningChallenge",
      })) as readonly [`0x${string}`, bigint, unknown];

      const [challengeNumber, target, rawSmhl] = miningChallenge;
      const smhl = normalizeSmhlChallenge(rawSmhl);

      const smhlStart = process.hrtime();
      const smhlSolution = await solveSmhlChallenge(smhl);
      const smhlElapsed = elapsedSeconds(smhlStart);

      const grind = await grindNonce(challengeNumber, target, account.address);

      console.log(
        `Submitting mine. SMHL ${smhlElapsed.toFixed(2)}s, hash grind ${grind.elapsed.toFixed(2)}s, ${grind.hashrate.toFixed(0)} H/s.`,
      );

      const txHash = await walletClient.writeContract({
        address: config.agentCoinAddress,
        abi: agentCoinAbi,
        account,
        functionName: "mine",
        args: [grind.nonce, smhlSolution, tokenId],
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });

      const [mineCount, earnings] = await Promise.all([
        publicClient.readContract({
          address: config.agentCoinAddress,
          abi: agentCoinAbi,
          functionName: "tokenMineCount",
          args: [tokenId],
        }) as Promise<bigint>,
        publicClient.readContract({
          address: config.agentCoinAddress,
          abi: agentCoinAbi,
          functionName: "tokenEarnings",
          args: [tokenId],
        }) as Promise<bigint>,
      ]);

      console.log(`Mine confirmed in tx ${receipt.transactionHash}`);
      console.log(`Nonce: ${grind.nonce.toString()} after ${grind.attempts.toString()} attempts`);
      console.log(`Token mines: ${mineCount.toString()}`);
      console.log(`Token earnings: ${formatEther(earnings)} AGENT`);

      await displayStats(tokenId);

      // FIX 3: Wait for block advancement before next iteration
      const lastMineBlock = (await publicClient.readContract({
        address: config.agentCoinAddress,
        abi: agentCoinAbi,
        functionName: "lastMineBlockNumber",
      })) as bigint;
      await waitForNextBlock(lastMineBlock);

      // Reset failures on success
      consecutiveFailures = 0;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);

      // FIX 5: Revert reason classification
      if (isFatalRevert(message)) {
        console.error(`Fatal error: ${message}. Exiting.`);
        return;
      }

      if (isBlockTooSoon(message)) {
        console.log("Block hasn't advanced yet. Waiting for next block...");
        const lastMineBlock = (await publicClient.readContract({
          address: config.agentCoinAddress,
          abi: agentCoinAbi,
          functionName: "lastMineBlockNumber",
        })) as bigint;
        await waitForNextBlock(lastMineBlock);
        continue;
      }

      // FIX 1: Exponential backoff + max failure exit
      consecutiveFailures += 1;
      if (consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
        console.error(
          `${MAX_CONSECUTIVE_FAILURES} consecutive failures. Last error: ${message}. Exiting.`,
        );
        return;
      }

      const delay = backoffMs(consecutiveFailures);
      console.error(
        `Mine attempt failed (${consecutiveFailures}/${MAX_CONSECUTIVE_FAILURES}): ${message}. Retrying in ${(delay / 1000).toFixed(1)}s.`,
      );
      await sleep(delay);
    }
  }
}
