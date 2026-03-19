/**
 * Testnet Multi-LLM Live Test
 *
 * Deploys the SMHL-retuned contracts to Base Sepolia, mints an NFT,
 * then mines one block with each LLM provider to verify solvability.
 *
 * Prerequisites (env vars):
 *   PRIVATE_KEY, BASE_SEPOLIA_RPC (or source contracts/.env)
 *   GEMINI_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY
 *
 * Usage:
 *   source ../contracts/.env && source ~/.secrets.env
 *   npx tsx testnet-llm-test.ts
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  formatEther,
  encodePacked,
  keccak256,
  hexToBytes,
  type Abi,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

import agentCoinAbiJson from "./src/abi/AgentCoin.json";
import miningAgentAbiJson from "./src/abi/MiningAgent.json";
import {
  normalizeSmhlChallenge,
  buildSmhlPrompt,
  validateSmhlSolution,
  type SmhlChallenge,
} from "./src/smhl";

const agentCoinAbi = agentCoinAbiJson as Abi;
const miningAgentAbi = miningAgentAbiJson as Abi;

// --- Deployed contract addresses (Base Sepolia, tolerant SMHL — length ±5, words ±2, char anywhere) ---
const MA_ADDR = "0xA00375Fe1E6d0f956a274992d4f9d44A71598baA" as Address;
const LP_ADDR = "0xbd0864FBd6d0e44119472BbefD6564Fd1291b4fE" as Address;
const AC_ADDR = "0x8C4bba84AaB5424c1C44b9D78651c0578287f348" as Address;

// --- LLM provider configs ---
interface LlmConfig {
  name: string;
  provider: string;
  model: string;
  apiKey: string;
}

function getLlmConfigs(): LlmConfig[] {
  const configs: LlmConfig[] = [];

  // Ordered weakest → strongest within each provider
  // Start with cheapest/fastest models, work up

  // --- OpenAI models (weakest → strongest) ---
  if (process.env.OPENAI_API_KEY) {
    configs.push({
      name: "GPT-5.4 Nano",
      provider: "openai",
      model: "gpt-5.4-nano",
      apiKey: process.env.OPENAI_API_KEY,
    });
    configs.push({
      name: "o4-mini",
      provider: "openai",
      model: "o4-mini",
      apiKey: process.env.OPENAI_API_KEY,
    });
    configs.push({
      name: "GPT-5.4 Mini",
      provider: "openai",
      model: "gpt-5.4-mini",
      apiKey: process.env.OPENAI_API_KEY,
    });
    configs.push({
      name: "GPT-5.3 Chat",
      provider: "openai",
      model: "gpt-5.3-chat-latest",
      apiKey: process.env.OPENAI_API_KEY,
    });
    configs.push({
      name: "o3",
      provider: "openai",
      model: "o3",
      apiKey: process.env.OPENAI_API_KEY,
    });
    configs.push({
      name: "GPT-5.4",
      provider: "openai",
      model: "gpt-5.4",
      apiKey: process.env.OPENAI_API_KEY,
    });
  }

  // --- Google Gemini 3.x family ---
  if (process.env.GEMINI_API_KEY) {
    configs.push({
      name: "Gemini 2.5 Flash",
      provider: "gemini",
      model: "gemini-2.5-flash",
      apiKey: process.env.GEMINI_API_KEY,
    });
    configs.push({
      name: "Gemini 3 Flash",
      provider: "gemini",
      model: "gemini-3-flash-preview",
      apiKey: process.env.GEMINI_API_KEY,
    });
    configs.push({
      name: "Gemini 3.1 Pro",
      provider: "gemini",
      model: "gemini-3.1-pro-preview",
      apiKey: process.env.GEMINI_API_KEY,
    });
  }

  // --- Anthropic Claude 4.x family ---
  if (process.env.ANTHROPIC_API_KEY) {
    configs.push({
      name: "Claude Haiku 4.5",
      provider: "anthropic",
      model: "claude-haiku-4-5-20251001",
      apiKey: process.env.ANTHROPIC_API_KEY,
    });
    configs.push({
      name: "Claude Sonnet 4.5",
      provider: "anthropic",
      model: "claude-sonnet-4-5-20250929",
      apiKey: process.env.ANTHROPIC_API_KEY,
    });
    configs.push({
      name: "Claude Opus 4.6",
      provider: "anthropic",
      model: "claude-opus-4-6",
      apiKey: process.env.ANTHROPIC_API_KEY,
    });
  }

  return configs;
}

// --- SMHL solver per provider (inline, no config module dependency) ---

async function solveWithGemini(prompt: string, apiKey: string, model: string): Promise<string> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        systemInstruction: {
          parts: [{ text: "You solve constrained ASCII string generation tasks. Return only the exact string requested." }],
        },
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0 },
      }),
    },
  );
  if (!res.ok) throw new Error(`Gemini ${res.status}: ${await res.text()}`);
  const data = (await res.json()) as any;
  return data.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
}

async function solveWithOpenAI(prompt: string, apiKey: string, model: string): Promise<string> {
  // o-series and gpt-5.3 models don't support temperature=0
  const isReasoningOrChat = model.startsWith("o") || model.includes("5.3");
  const body: any = {
    model,
    messages: [
      ...(isReasoningOrChat ? [] : [{ role: "system", content: "You solve constrained ASCII string generation tasks. Return only the exact string requested." }]),
      { role: "user", content: (isReasoningOrChat ? "You solve constrained ASCII string generation tasks. Return only the exact string requested.\n\n" : "") + prompt },
    ],
  };
  if (!isReasoningOrChat) {
    body.temperature = 0;
  }

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${await res.text()}`);
  const data = (await res.json()) as any;
  return data.choices?.[0]?.message?.content ?? "";
}

async function solveWithAnthropic(prompt: string, apiKey: string, model: string): Promise<string> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      max_tokens: 200,
      temperature: 0,
      system: "You solve constrained ASCII string generation tasks. Return only the exact string requested.",
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!res.ok) throw new Error(`Anthropic ${res.status}: ${await res.text()}`);
  const data = (await res.json()) as any;
  return data.content?.find((c: any) => c.type === "text")?.text ?? "";
}

function cleanLlmResponse(raw: string): string {
  let cleaned = raw.replace(/\r/g, "").trim();
  // Strip code fences
  const fenceMatch = cleaned.match(/^```(?:text)?\n([\s\S]*?)\n```$/);
  if (fenceMatch) cleaned = fenceMatch[1];
  // Strip wrapping quotes
  if (
    (cleaned.startsWith('"') && cleaned.endsWith('"')) ||
    (cleaned.startsWith("'") && cleaned.endsWith("'"))
  ) {
    cleaned = cleaned.slice(1, -1);
  }
  // If multi-line, take the first non-empty line (LLM might explain after)
  const lines = cleaned.split("\n").map((l) => l.trim()).filter(Boolean);
  if (lines.length > 1) cleaned = lines[0];
  return cleaned;
}

async function callLlm(prompt: string, llm: LlmConfig): Promise<string> {
  switch (llm.provider) {
    case "gemini":
      return solveWithGemini(prompt, llm.apiKey, llm.model);
    case "openai":
      return solveWithOpenAI(prompt, llm.apiKey, llm.model);
    case "anthropic":
      return solveWithAnthropic(prompt, llm.apiKey, llm.model);
    default:
      throw new Error(`Unknown provider: ${llm.provider}`);
  }
}

async function solveSmhl(
  challenge: SmhlChallenge,
  llm: LlmConfig,
): Promise<{ solution: string; attempts: number; issues: string[] }> {
  const basePrompt = buildSmhlPrompt(challenge);

  for (let attempt = 1; attempt <= 3; attempt++) {
    let prompt: string;
    if (attempt === 1) {
      prompt = basePrompt;
    } else {
      // Self-correction: include previous errors
      prompt = basePrompt + "\n\n" +
        `IMPORTANT: Your previous attempt failed with these errors:\n${lastIssues.join("\n")}\n` +
        `Fix these specific issues. Double-check character count and word count before responding.`;
    }

    const raw = await callLlm(prompt, llm);
    const cleaned = cleanLlmResponse(raw);

    const issues = validateSmhlSolution(cleaned, challenge);
    if (issues.length === 0) {
      return { solution: cleaned, attempts: attempt, issues: [] };
    }

    var lastIssues = issues.map((i) => `- ${i}`);

    if (attempt === 3) {
      return { solution: cleaned, attempts: 3, issues };
    }
  }

  return { solution: "", attempts: 3, issues: ["exhausted retries"] };
}

// --- Challenge derivation (matches updated contract with 126 ceiling) ---

function deriveChallengeFromSeed(seed: Hex): SmhlChallenge {
  const bytes = hexToBytes(seed);
  const firstNChars = 5 + (bytes[0] % 6);
  const wordCount = 3 + (bytes[2] % 5);
  const totalLength = 20 + (bytes[5] % 31);
  const charPosition = bytes[3] % totalLength;
  const charValue = 97 + (bytes[4] % 26);

  let targetAsciiSum = 400 + bytes[1] * 3;
  let maxAsciiSum = firstNChars * 126;
  if (charPosition < firstNChars) {
    maxAsciiSum = maxAsciiSum - 126 + charValue;
  }
  if (targetAsciiSum > maxAsciiSum) {
    targetAsciiSum = 400 + ((targetAsciiSum - 400) % (maxAsciiSum - 399));
  }

  return normalizeSmhlChallenge([targetAsciiSum, firstNChars, wordCount, charPosition, charValue, totalLength]);
}

// --- Deterministic solver (mirrors Solidity test helper _solveSMHL) ---

function deterministicSolve(c: SmhlChallenge): string {
  const solution = new Uint8Array(c.totalLength);
  const isSpace = new Array(c.totalLength).fill(false);

  // Fill with 'A' (65)
  for (let i = 0; i < c.totalLength; i++) solution[i] = 65;

  // Place required character
  solution[c.charPosition] = c.charValue;

  // Place spaces for word boundaries (wordCount-1 spaces needed)
  const spacesNeeded = c.wordCount - 1;
  let spacesPlaced = 0;

  // Try placing spaces after firstNChars first
  if (c.totalLength > c.firstNChars) {
    let pos = c.totalLength - 2;
    while (spacesPlaced < spacesNeeded && pos >= c.firstNChars) {
      if (
        pos !== c.charPosition &&
        !isSpace[pos] &&
        !(pos > 0 && isSpace[pos - 1]) &&
        !(pos + 1 < c.totalLength && isSpace[pos + 1])
      ) {
        solution[pos] = 32;
        isSpace[pos] = true;
        spacesPlaced++;
      }
      if (pos === c.firstNChars) break;
      pos--;
    }
  }

  // If more spaces needed, place within firstNChars
  if (spacesPlaced < spacesNeeded && c.firstNChars > 1) {
    let pos = c.firstNChars - 1;
    while (spacesPlaced < spacesNeeded && pos >= 1) {
      if (
        pos !== c.charPosition &&
        !isSpace[pos] &&
        !(pos > 0 && isSpace[pos - 1]) &&
        !(pos + 1 < c.totalLength && isSpace[pos + 1])
      ) {
        solution[pos] = 32;
        isSpace[pos] = true;
        spacesPlaced++;
      }
      if (pos === 1) break;
      pos--;
    }
  }

  if (spacesPlaced !== spacesNeeded) throw new Error("Cannot place spaces");

  // Calculate current ASCII sum of firstNChars and set base to '!' (33)
  let currentSum = 0;
  for (let i = 0; i < c.firstNChars; i++) {
    if (isSpace[i]) {
      currentSum += 32;
    } else if (i === c.charPosition) {
      currentSum += c.charValue;
    } else {
      solution[i] = 33; // '!'
      currentSum += 33;
    }
  }

  // Distribute remaining ASCII sum
  let remaining = c.targetAsciiSum - currentSum;
  for (let i = 0; i < c.firstNChars && remaining > 0; i++) {
    if (i === c.charPosition || isSpace[i]) continue;
    const maxAdd = 126 - solution[i];
    const add = remaining > maxAdd ? maxAdd : remaining;
    solution[i] = solution[i] + add;
    remaining -= add;
  }

  if (remaining > 0) throw new Error(`Unsolvable: ${remaining} remaining`);

  // Ensure charValue is correct (may have been overwritten)
  solution[c.charPosition] = c.charValue;

  return String.fromCharCode(...solution);
}

// --- Nonce grinding ---

function findNonce(challengeNumber: Hex, miner: Address, target: bigint, maxIter = 5_000_000): bigint {
  for (let i = 0n; i < BigInt(maxIter); i++) {
    const digest = BigInt(keccak256(encodePacked(["bytes32", "address", "uint256"], [challengeNumber, miner, i])));
    if (digest < target) return i;
  }
  throw new Error("No valid nonce found");
}

// --- Main ---

async function main() {
  // Setup clients
  const pk = process.env.PRIVATE_KEY as Hex;
  const rpcUrl = process.env.BASE_SEPOLIA_RPC!;

  if (!pk) throw new Error("PRIVATE_KEY not set");
  if (!rpcUrl) throw new Error("BASE_SEPOLIA_RPC not set");

  const account = privateKeyToAccount(pk);
  const publicClient = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
  const walletClient = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });

  const llmConfigs = getLlmConfigs();

  console.log(`\n  === SMHL Testnet Multi-LLM Test ===`);
  console.log(`  Chain: Base Sepolia (84532)`);
  console.log(`  Deployer: ${account.address}`);
  console.log(`  MiningAgent: ${MA_ADDR}`);
  console.log(`  AgentCoin: ${AC_ADDR}`);
  console.log(`  LPVault: ${LP_ADDR}`);
  console.log(`  LLM providers: ${llmConfigs.map((c) => c.name).join(", ")}`);

  const balance = await publicClient.getBalance({ address: account.address });
  console.log(`  Balance: ${formatEther(balance)} ETH\n`);

  // Step 1: Finish contract wiring if needed
  console.log(`  Step 1: Verifying contract wiring...`);

  // Admin ABI entries not in the miner's stripped ABI
  const adminAbi = [
    { type: "function", name: "agentCoin", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
    { type: "function", name: "setAgentCoin", inputs: [{ name: "_agentCoin", type: "address" }], outputs: [], stateMutability: "nonpayable" },
    { type: "function", name: "lpVault", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
    { type: "function", name: "setLPVault", inputs: [{ name: "_lpVault", type: "address" }], outputs: [], stateMutability: "nonpayable" },
  ] as const;

  const currentAgentCoin = await publicClient.readContract({
    address: MA_ADDR,
    abi: adminAbi,
    functionName: "agentCoin",
  });

  if (currentAgentCoin === "0x0000000000000000000000000000000000000000") {
    console.log(`    Setting AgentCoin on MiningAgent...`);
    const tx1 = await walletClient.writeContract({
      address: MA_ADDR,
      abi: adminAbi,
      functionName: "setAgentCoin",
      args: [AC_ADDR],
    });
    await publicClient.waitForTransactionReceipt({ hash: tx1 });
    console.log(`    Done: ${tx1}`);
  } else {
    console.log(`    MiningAgent.agentCoin already set: ${currentAgentCoin}`);
  }

  const lpAgentCoin = await publicClient.readContract({
    address: LP_ADDR,
    abi: adminAbi,
    functionName: "agentCoin",
  });

  if (lpAgentCoin === "0x0000000000000000000000000000000000000000") {
    console.log(`    Setting AgentCoin on LPVault...`);
    const tx2 = await walletClient.writeContract({
      address: LP_ADDR,
      abi: adminAbi,
      functionName: "setAgentCoin",
      args: [AC_ADDR],
    });
    await publicClient.waitForTransactionReceipt({ hash: tx2 });
    console.log(`    Done: ${tx2}`);
  } else {
    console.log(`    LPVault.agentCoin already set: ${lpAgentCoin}`);
  }

  console.log(`    Wiring complete.\n`);

  // Step 2: Find or mint an NFT
  console.log(`  Step 2: Finding or minting NFT...`);

  // Check if we already own a token (from prior runs)
  const ownedCount = (await publicClient.readContract({
    address: MA_ADDR,
    abi: miningAgentAbi,
    functionName: "balanceOf",
    args: [account.address],
  })) as bigint;

  let mintedTokenId: bigint;

  if (ownedCount > 0n) {
    // Use existing token
    mintedTokenId = (await publicClient.readContract({
      address: MA_ADDR,
      abi: miningAgentAbi,
      functionName: "tokenOfOwnerByIndex",
      args: [account.address, 0n],
    })) as bigint;
    console.log(`    Already own token #${mintedTokenId}, skipping mint.\n`);
  } else {
    // Need to mint
    const mintLlm = llmConfigs[0];
    console.log(`    Using ${mintLlm.name} for mint SMHL...`);

    const mintPrice = (await publicClient.readContract({
      address: MA_ADDR,
      abi: miningAgentAbi,
      functionName: "getMintPrice",
    })) as bigint;
    console.log(`    Mint price: ${formatEther(mintPrice)} ETH`);

    const MAX_MINT_RETRIES = 5;
    let minted = false;

    for (let mintAttempt = 1; mintAttempt <= MAX_MINT_RETRIES; mintAttempt++) {
      console.log(`    Mint attempt ${mintAttempt}/${MAX_MINT_RETRIES}...`);

      const challengeTx = await walletClient.writeContract({
        address: MA_ADDR,
        abi: miningAgentAbi,
        functionName: "getChallenge",
        args: [account.address],
      });
      await publicClient.waitForTransactionReceipt({ hash: challengeTx });

      // Short delay for state propagation, then read seed
      await new Promise((r) => setTimeout(r, 1000));
      const seedClient = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
      const challengeSeed = (await seedClient.readContract({
        address: MA_ADDR,
        abi: miningAgentAbi,
        functionName: "challengeSeeds",
        args: [account.address],
      })) as Hex;

      const mintChallenge = deriveChallengeFromSeed(challengeSeed);
      console.log(`    Challenge: len=${mintChallenge.totalLength}, words=${mintChallenge.wordCount}, target=${mintChallenge.targetAsciiSum}`);

      // Use deterministic solver (fast + reliable) — LLM testing happens in step 3
      const solutionToSubmit = deterministicSolve(mintChallenge);

      try {
        await seedClient.simulateContract({
          address: MA_ADDR,
          abi: miningAgentAbi,
          functionName: "mint",
          args: [solutionToSubmit],
          value: mintPrice,
          account: account,
        });
      } catch (simErr: any) {
        console.log(`    Simulation: FAIL — ${simErr.message?.substring(0, 200)}`);
        continue;
      }

      const mintTx = await walletClient.writeContract({
        address: MA_ADDR,
        abi: miningAgentAbi,
        functionName: "mint",
        args: [solutionToSubmit],
        value: mintPrice,
      });
      const mintReceipt = await publicClient.waitForTransactionReceipt({ hash: mintTx });

      if (mintReceipt.status !== "success") {
        console.log(`    Mint tx reverted!`);
        continue;
      }

      // Read the actual minted token ID from owner's token list
      await new Promise((r) => setTimeout(r, 2000)); // wait for state propagation
      const freshOwner = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
      mintedTokenId = (await freshOwner.readContract({
        address: MA_ADDR,
        abi: miningAgentAbi,
        functionName: "tokenOfOwnerByIndex",
        args: [account.address, 0n],
      })) as bigint;

      console.log(`    Minted NFT #${mintedTokenId}`);
      console.log(`    Tx: ${mintReceipt.transactionHash}\n`);
      minted = true;
      break;
    }

    if (!minted) {
      console.log(`    Mint failed after all attempts. Aborting.`);
      process.exit(1);
    }
  }

  // Step 3: Mine with each LLM
  console.log(`  Step 3: Mining with each LLM provider...\n`);

  const results: { name: string; success: boolean; attempts: number; elapsed: number; error?: string; txHash?: string }[] = [];

  for (let i = 0; i < llmConfigs.length; i++) {
    const llm = llmConfigs[i];
    console.log(`  --- ${llm.name} (${llm.model}) ---`);
    const start = Date.now();

    try {
      // Wait for block advancement (one mine per block) — use fresh client to avoid cache
      const blockClient = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
      const lastMineBlock = (await blockClient.readContract({
        address: AC_ADDR,
        abi: agentCoinAbi,
        functionName: "lastMineBlockNumber",
      })) as bigint;

      let currentBlock = await blockClient.getBlockNumber();
      if (currentBlock <= lastMineBlock) {
        console.log(`    Waiting for block ${lastMineBlock + 1n}...`);
        while (currentBlock <= lastMineBlock) {
          await new Promise((r) => setTimeout(r, 2000));
          currentBlock = await blockClient.getBlockNumber();
        }
      }

      // Get mining challenge (derived from current block hash) — fresh client
      const challengeClient = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
      const [challengeNumber, miningTarget, smhlRaw] = (await challengeClient.readContract({
        address: AC_ADDR,
        abi: agentCoinAbi,
        functionName: "getMiningChallenge",
      })) as [Hex, bigint, any];

      const challenge = normalizeSmhlChallenge(smhlRaw);
      console.log(`    Challenge: len=${challenge.totalLength}, words=${challenge.wordCount}, firstN=${challenge.firstNChars}, target=${challenge.targetAsciiSum}, char@${challenge.charPosition}='${String.fromCharCode(challenge.charValue)}'`);

      // Solve SMHL with LLM
      const result = await solveSmhl(challenge, llm);
      let smhlSolution: string;
      let llmPassed: boolean;

      if (result.issues.length === 0) {
        smhlSolution = result.solution;
        llmPassed = true;
        console.log(`    LLM SMHL solved in ${result.attempts} attempt(s): "${result.solution.substring(0, 30)}..."`);
      } else {
        console.log(`    LLM SMHL failed: ${result.issues.join(", ")}`);
        // Use deterministic solver as fallback so we can test the mine tx
        smhlSolution = deterministicSolve(challenge);
        llmPassed = false;
        console.log(`    Using deterministic fallback for mine tx.`);
      }

      // Re-read challenge (block may have advanced during LLM call) — fresh client
      const freshMineClient = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
      const [freshChallengeNumber, freshTarget, freshSmhlRaw] = (await freshMineClient.readContract({
        address: AC_ADDR,
        abi: agentCoinAbi,
        functionName: "getMiningChallenge",
      })) as [Hex, bigint, any];

      if (freshChallengeNumber !== challengeNumber) {
        console.log(`    Block advanced during solve — re-solving with deterministic...`);
        const freshChallenge = normalizeSmhlChallenge(freshSmhlRaw);
        smhlSolution = deterministicSolve(freshChallenge);
        llmPassed = false; // Can't credit LLM since challenge changed
      }

      // Grind nonce for the CURRENT challenge
      console.log(`    Grinding nonce (target: ${freshTarget.toString(16).substring(0, 12)}...)...`);
      const nonce = findNonce(freshChallengeNumber, account.address, freshTarget);
      console.log(`    Found nonce: ${nonce}`);

      // Submit mine tx
      const mineTx = await walletClient.writeContract({
        address: AC_ADDR,
        abi: agentCoinAbi,
        functionName: "mine",
        args: [nonce, smhlSolution, mintedTokenId],
      });
      const mineReceipt = await publicClient.waitForTransactionReceipt({ hash: mineTx });

      const elapsed = (Date.now() - start) / 1000;
      if (mineReceipt.status === "success") {
        const mineStatus = llmPassed ? "MINED (LLM)" : "MINED (deterministic fallback)";
        console.log(`    ${mineStatus}! Tx: ${mineReceipt.transactionHash}`);
        results.push({ name: llm.name, success: llmPassed, attempts: result.attempts, elapsed, txHash: mineReceipt.transactionHash });
      } else {
        console.log(`    TX REVERTED: ${mineReceipt.transactionHash}`);
        results.push({ name: llm.name, success: false, attempts: result.attempts, elapsed, error: "tx reverted" });
      }
    } catch (err) {
      const elapsed = (Date.now() - start) / 1000;
      const errMsg = err instanceof Error ? err.message : String(err);
      console.log(`    ERROR: ${errMsg.substring(0, 200)}`);
      results.push({ name: llm.name, success: false, attempts: 0, elapsed, error: errMsg.substring(0, 100) });
    }

    // Wait for block advancement before next provider (avoid "one mine per block")
    if (i < llmConfigs.length - 1) {
      const waitClient = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
      const curBlock = await waitClient.getBlockNumber();
      console.log(`    Waiting for next block (currently ${curBlock})...`);
      let nextBlock = curBlock;
      while (nextBlock <= curBlock) {
        await new Promise((r) => setTimeout(r, 2000));
        nextBlock = await createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) }).getBlockNumber();
      }
      console.log(`    Block ${nextBlock} ready.`);
    }

    console.log("");
  }

  // Summary
  console.log(`  ========================================`);
  console.log(`  RESULTS`);
  console.log(`  ========================================`);

  for (const r of results) {
    const status = r.success ? "PASS" : "FAIL";
    const symbol = r.success ? "+" : "x";
    console.log(`  [${symbol}] ${r.name}: ${status} (${r.attempts} attempts, ${r.elapsed.toFixed(1)}s)${r.error ? ` — ${r.error}` : ""}${r.txHash ? ` — ${r.txHash.substring(0, 18)}...` : ""}`);
  }

  const passed = results.filter((r) => r.success).length;
  console.log(`\n  ${passed}/${results.length} providers passed.\n`);

  // Final stats
  const totalMines = (await publicClient.readContract({
    address: AC_ADDR,
    abi: agentCoinAbi,
    functionName: "totalMines",
  })) as bigint;

  const totalMinted = (await publicClient.readContract({
    address: AC_ADDR,
    abi: agentCoinAbi,
    functionName: "totalMinted",
  })) as bigint;

  console.log(`  On-chain stats:`);
  console.log(`    Total mines: ${totalMines}`);
  console.log(`    Total minted: ${formatEther(totalMinted)} AGENT`);
  console.log("");
}

main().catch((err) => {
  console.error(`\n  Fatal error: ${err.message}\n`);
  process.exit(1);
});
