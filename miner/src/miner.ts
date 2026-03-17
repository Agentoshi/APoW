import type { Abi } from "viem";
import { encodePacked, formatEther, keccak256 } from "viem";

import agentCoinAbiJson from "./abi/AgentCoin.json";
import { config } from "./config";
import { normalizeSmhlChallenge, solveSmhlChallenge } from "./smhl";
import { displayStats } from "./stats";
import { publicClient, requireWallet } from "./wallet";

const agentCoinAbi = agentCoinAbiJson as Abi;

function elapsedSeconds(start: [number, number]): number {
  const [seconds, nanoseconds] = process.hrtime(start);
  return seconds + nanoseconds / 1_000_000_000;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

  console.log(`Starting mining loop with token #${tokenId.toString()} on ${config.chain.name}.`);

  while (true) {
    try {
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
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error(`Mine attempt failed: ${message}`);
      await sleep(2_000);
    }
  }
}
