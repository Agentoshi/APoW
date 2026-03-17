import type { Abi, Address, Hex } from "viem";
import { formatEther, hexToBytes } from "viem";

import miningAgentAbiJson from "./abi/MiningAgent.json";
import { config } from "./config";
import { normalizeSmhlChallenge, solveSmhlChallenge, type SmhlChallenge } from "./smhl";
import { publicClient, requireWallet } from "./wallet";

const miningAgentAbi = miningAgentAbiJson as Abi;
const ZERO_SEED = `0x${"0".repeat(64)}` as Hex;
const rarityLabels = ["Common", "Uncommon", "Rare", "Epic", "Mythic"] as const;

function deriveChallengeFromSeed(seed: Hex): SmhlChallenge {
  const bytes = hexToBytes(seed);
  const firstNChars = 5 + (bytes[0] % 6);
  const wordCount = 3 + (bytes[2] % 5);
  const totalLength = 20 + (bytes[5] % 31);
  const charPosition = bytes[3] % totalLength;
  const charValue = 97 + (bytes[4] % 26);

  let targetAsciiSum = 400 + (bytes[1] * 3);
  let maxAsciiSum = firstNChars * 255;
  if (charPosition < firstNChars) {
    maxAsciiSum = maxAsciiSum - 255 + charValue;
  }

  if (targetAsciiSum > maxAsciiSum) {
    targetAsciiSum = 400 + ((targetAsciiSum - 400) % (maxAsciiSum - 399));
  }

  return normalizeSmhlChallenge([
    targetAsciiSum,
    firstNChars,
    wordCount,
    charPosition,
    charValue,
    totalLength,
  ]);
}

function formatHashpower(hashpower: number): string {
  return `${(hashpower / 100).toFixed(2)}x`;
}

async function findMintedTokenId(
  startTokenId: bigint,
  endTokenIdExclusive: bigint,
  owner: Address,
  blockNumber: bigint,
): Promise<bigint> {
  for (let tokenId = startTokenId; tokenId < endTokenIdExclusive; tokenId += 1n) {
    try {
      const [tokenOwner, mintBlock] = await Promise.all([
        publicClient.readContract({
          address: config.miningAgentAddress,
          abi: miningAgentAbi,
          functionName: "ownerOf",
          args: [tokenId],
        }) as Promise<Address>,
        publicClient.readContract({
          address: config.miningAgentAddress,
          abi: miningAgentAbi,
          functionName: "mintBlock",
          args: [tokenId],
        }) as Promise<bigint>,
      ]);

      if (tokenOwner.toLowerCase() === owner.toLowerCase() && mintBlock === blockNumber) {
        return tokenId;
      }
    } catch {
      // Ignore missing token ids while scanning the minted window.
    }
  }

  throw new Error("Unable to determine minted token ID from post-mint contract state.");
}

export async function runMintFlow(): Promise<void> {
  const { account, walletClient } = requireWallet();

  console.log(`Requesting mint challenge for ${account.address}...`);
  const challengeTx = await walletClient.writeContract({
    address: config.miningAgentAddress,
    abi: miningAgentAbi,
    account,
    functionName: "getChallenge",
    args: [account.address],
  });
  await publicClient.waitForTransactionReceipt({ hash: challengeTx });

  const challengeSeed = (await publicClient.readContract({
    address: config.miningAgentAddress,
    abi: miningAgentAbi,
    functionName: "challengeSeeds",
    args: [account.address],
  })) as Hex;

  if (challengeSeed.toLowerCase() === ZERO_SEED.toLowerCase()) {
    throw new Error("Challenge seed was not stored on-chain.");
  }

  const challenge = deriveChallengeFromSeed(challengeSeed);
  console.log("Solving SMHL challenge...");
  const solution = await solveSmhlChallenge(challenge);

  const [mintPrice, nextTokenIdBefore] = await Promise.all([
    publicClient.readContract({
      address: config.miningAgentAddress,
      abi: miningAgentAbi,
      functionName: "getMintPrice",
    }) as Promise<bigint>,
    publicClient.readContract({
      address: config.miningAgentAddress,
      abi: miningAgentAbi,
      functionName: "nextTokenId",
    }) as Promise<bigint>,
  ]);

  console.log(`Minting miner for ${formatEther(mintPrice)} ETH...`);
  const mintTx = await walletClient.writeContract({
    address: config.miningAgentAddress,
    abi: miningAgentAbi,
    account,
    functionName: "mint",
    args: [solution],
    value: mintPrice,
  });
  const receipt = await publicClient.waitForTransactionReceipt({ hash: mintTx });
  const nextTokenIdAfter = (await publicClient.readContract({
    address: config.miningAgentAddress,
    abi: miningAgentAbi,
    functionName: "nextTokenId",
  })) as bigint;

  const tokenId = await findMintedTokenId(
    nextTokenIdBefore,
    nextTokenIdAfter,
    account.address,
    receipt.blockNumber,
  );

  const [rarityRaw, hashpowerRaw] = await Promise.all([
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
  ]);
  const rarity = Number(rarityRaw);
  const hashpower = Number(hashpowerRaw);

  console.log("Mint complete.");
  console.log(`Token ID: ${tokenId.toString()}`);
  console.log(`Rarity: ${rarityLabels[rarity] ?? `Tier ${rarity}`}`);
  console.log(`Hashpower: ${formatHashpower(hashpower)}`);
  console.log(`Transaction: ${receipt.transactionHash}`);
}
