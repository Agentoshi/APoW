import type { Abi } from "viem";
import { formatEther } from "viem";

import agentCoinAbiJson from "./abi/AgentCoin.json";
import miningAgentAbiJson from "./abi/MiningAgent.json";
import { config } from "./config";
import { account, publicClient } from "./wallet";

const miningAgentAbi = miningAgentAbiJson as Abi;
const agentCoinAbi = agentCoinAbiJson as Abi;
const rarityLabels = ["Common", "Uncommon", "Rare", "Epic", "Mythic"] as const;

function formatHashpower(hashpower: number): string {
  return `${(hashpower / 100).toFixed(2)}x`;
}

export async function displayStats(tokenId?: bigint): Promise<void> {
  const [totalMines, totalMinted, miningTarget, walletBalance] = await Promise.all([
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
      functionName: "miningTarget",
    }) as Promise<bigint>,
    account
      ? (publicClient.readContract({
          address: config.agentCoinAddress,
          abi: agentCoinAbi,
          functionName: "balanceOf",
          args: [account.address],
        }) as Promise<bigint>)
      : Promise.resolve(0n),
  ]);

  console.log("Network stats");
  console.log(`Total mines: ${totalMines.toString()}`);
  console.log(`Total minted: ${formatEther(totalMinted)} AGENT`);
  console.log(`Mining target: ${miningTarget.toString()}`);
  if (account) {
    console.log(`Wallet balance: ${formatEther(walletBalance)} AGENT`);
  }

  if (tokenId === undefined) {
    return;
  }

  const [tokenMineCount, tokenEarnings, rarityRaw, hashpowerRaw, mintBlock] = await Promise.all([
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
    publicClient.readContract({
      address: config.miningAgentAddress,
      abi: miningAgentAbi,
      functionName: "rarity",
      args: [tokenId],
    }) as Promise<bigint>,
    publicClient.readContract({
      address: config.miningAgentAddress,
      abi: miningAgentAbi,
      functionName: "hashpower",
      args: [tokenId],
    }) as Promise<bigint>,
    publicClient.readContract({
      address: config.miningAgentAddress,
      abi: miningAgentAbi,
      functionName: "mintBlock",
      args: [tokenId],
    }) as Promise<bigint>,
  ]);
  const rarity = Number(rarityRaw);
  const hashpower = Number(hashpowerRaw);

  console.log("");
  console.log(`Miner #${tokenId.toString()}`);
  console.log(`Rarity: ${rarityLabels[rarity] ?? `Tier ${rarity}`}`);
  console.log(`Hashpower: ${formatHashpower(hashpower)}`);
  console.log(`Mint block: ${mintBlock.toString()}`);
  console.log(`Mine count: ${tokenMineCount.toString()}`);
  console.log(`Earnings: ${formatEther(tokenEarnings)} AGENT`);
}
