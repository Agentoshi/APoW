/**
 * Local SMHL Test — No gas costs, no on-chain interaction.
 * Tests whether each LLM can solve the simplified SMHL challenge
 * (length + word count + char position — no ASCII sum check).
 *
 * Usage:
 *   source ~/.secrets.env && npx tsx smhl-local-test.ts
 */

import { hexToBytes, keccak256, encodePacked, type Hex } from "viem";
import {
  normalizeSmhlChallenge,
  buildSmhlPrompt,
  validateSmhlSolution,
  type SmhlChallenge,
} from "./src/smhl";

// --- LLM configs ---

interface LlmConfig {
  name: string;
  provider: string;
  model: string;
  apiKey: string;
}

function getLlmConfigs(): LlmConfig[] {
  const configs: LlmConfig[] = [];

  if (process.env.OPENAI_API_KEY) {
    for (const [name, model] of [
      ["GPT-5.4 Nano", "gpt-5.4-nano"],
      ["o4-mini", "o4-mini"],
      ["GPT-5.4 Mini", "gpt-5.4-mini"],
      ["GPT-5.3 Chat", "gpt-5.3-chat-latest"],
      ["o3", "o3"],
      ["GPT-5.4", "gpt-5.4"],
    ]) {
      configs.push({ name, provider: "openai", model, apiKey: process.env.OPENAI_API_KEY! });
    }
  }

  if (process.env.GEMINI_API_KEY) {
    for (const [name, model] of [
      ["Gemini 2.5 Flash", "gemini-2.5-flash"],
      ["Gemini 3 Flash", "gemini-3-flash-preview"],
      ["Gemini 3.1 Pro", "gemini-3.1-pro-preview"],
    ]) {
      configs.push({ name, provider: "gemini", model, apiKey: process.env.GEMINI_API_KEY! });
    }
  }

  if (process.env.ANTHROPIC_API_KEY) {
    for (const [name, model] of [
      ["Claude Haiku 4.5", "claude-haiku-4-5-20251001"],
      ["Claude Sonnet 4.5", "claude-sonnet-4-5-20250929"],
      ["Claude Opus 4.6", "claude-opus-4-6"],
    ]) {
      configs.push({ name, provider: "anthropic", model, apiKey: process.env.ANTHROPIC_API_KEY! });
    }
  }

  return configs;
}

// --- LLM callers ---

async function solveWithGemini(prompt: string, apiKey: string, model: string): Promise<string> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        systemInstruction: {
          parts: [{ text: "You generate strings that match exact constraints. Return only the string." }],
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
  const isReasoning = model.startsWith("o") || model.includes("5.3");
  const body: any = {
    model,
    messages: [
      ...(isReasoning ? [] : [{ role: "system", content: "You generate strings that match exact constraints. Return only the string." }]),
      { role: "user", content: (isReasoning ? "You generate strings that match exact constraints. Return only the string.\n\n" : "") + prompt },
    ],
  };
  if (!isReasoning) body.temperature = 0;

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${apiKey}` },
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
      system: "You generate strings that match exact constraints. Return only the string.",
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!res.ok) throw new Error(`Anthropic ${res.status}: ${await res.text()}`);
  const data = (await res.json()) as any;
  return data.content?.find((c: any) => c.type === "text")?.text ?? "";
}

function cleanResponse(raw: string): string {
  let cleaned = raw.replace(/\r/g, "").trim();
  const fence = cleaned.match(/^```(?:text)?\n([\s\S]*?)\n```$/);
  if (fence) cleaned = fence[1];
  if ((cleaned.startsWith('"') && cleaned.endsWith('"')) || (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
    cleaned = cleaned.slice(1, -1);
  }
  const lines = cleaned.split("\n").map((l) => l.trim()).filter(Boolean);
  if (lines.length > 1) cleaned = lines[0];
  return cleaned;
}

async function callLlm(prompt: string, llm: LlmConfig): Promise<string> {
  switch (llm.provider) {
    case "gemini": return solveWithGemini(prompt, llm.apiKey, llm.model);
    case "openai": return solveWithOpenAI(prompt, llm.apiKey, llm.model);
    case "anthropic": return solveWithAnthropic(prompt, llm.apiKey, llm.model);
    default: throw new Error(`Unknown provider: ${llm.provider}`);
  }
}

// --- Challenge generation (mirrors contract _deriveChallenge) ---

function deriveChallengeFromSeed(seed: Hex): SmhlChallenge {
  const bytes = hexToBytes(seed);
  const firstNChars = 5 + (bytes[0] % 6);
  const wordCount = 3 + (bytes[2] % 5);
  const totalLength = 20 + (bytes[5] % 31);
  const charPosition = bytes[3] % totalLength;
  const charValue = 97 + (bytes[4] % 26);

  let targetAsciiSum = 400 + bytes[1] * 3;
  let maxAsciiSum = firstNChars * 126;
  if (charPosition < firstNChars) maxAsciiSum = maxAsciiSum - 126 + charValue;
  if (targetAsciiSum > maxAsciiSum) targetAsciiSum = 400 + ((targetAsciiSum - 400) % (maxAsciiSum - 399));

  return normalizeSmhlChallenge([targetAsciiSum, firstNChars, wordCount, charPosition, charValue, totalLength]);
}

// --- Main ---

async function main() {
  const llmConfigs = getLlmConfigs();
  if (llmConfigs.length === 0) {
    console.error("No API keys set. Set OPENAI_API_KEY, GEMINI_API_KEY, ANTHROPIC_API_KEY.");
    process.exit(1);
  }

  // Generate 3 random challenges from deterministic seeds
  const seeds: Hex[] = [
    keccak256(encodePacked(["string"], ["test-seed-1"])),
    keccak256(encodePacked(["string"], ["test-seed-2"])),
    keccak256(encodePacked(["string"], ["test-seed-3"])),
  ];

  const challenges = seeds.map((s) => deriveChallengeFromSeed(s));

  console.log(`\n  === Local SMHL Test (Tolerant — length ±5, words ±2, char anywhere) ===`);
  console.log(`  Models: ${llmConfigs.map((c) => c.name).join(", ")}`);
  console.log(`  Challenges: ${challenges.length}\n`);

  for (let ci = 0; ci < challenges.length; ci++) {
    const c = challenges[ci];
    console.log(`  Challenge ${ci + 1}: len≈${c.totalLength}, words≈${c.wordCount}, must contain '${String.fromCharCode(c.charValue)}'`);
  }
  console.log("");

  const results: { name: string; passed: number; failed: number; details: string[] }[] = [];

  for (const llm of llmConfigs) {
    console.log(`  --- ${llm.name} (${llm.model}) ---`);
    let passed = 0;
    let failed = 0;
    const details: string[] = [];

    for (let ci = 0; ci < challenges.length; ci++) {
      const challenge = challenges[ci];
      const prompt = buildSmhlPrompt(challenge);

      let success = false;
      for (let attempt = 1; attempt <= 3; attempt++) {
        try {
          const raw = await callLlm(prompt, llm);
          const cleaned = cleanResponse(raw);
          const issues = validateSmhlSolution(cleaned, challenge);

          if (issues.length === 0) {
            console.log(`    C${ci + 1}: PASS (attempt ${attempt}) — "${cleaned.substring(0, 50)}${cleaned.length > 50 ? "..." : ""}"`);
            success = true;
            break;
          }

          if (attempt === 3) {
            console.log(`    C${ci + 1}: FAIL — ${issues.join(", ")}`);
            console.log(`           Response: "${cleaned.substring(0, 60)}"`);
            details.push(`C${ci + 1}: ${issues.join(", ")}`);
          }
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          if (attempt === 3) {
            console.log(`    C${ci + 1}: ERROR — ${msg.substring(0, 100)}`);
            details.push(`C${ci + 1}: ERROR`);
          }
        }
      }

      if (success) passed++;
      else failed++;
    }

    results.push({ name: llm.name, passed, failed, details });
    console.log("");
  }

  // Summary
  console.log(`  ========================================`);
  console.log(`  RESULTS (${challenges.length} challenges per model)`);
  console.log(`  ========================================`);

  for (const r of results) {
    const pct = ((r.passed / (r.passed + r.failed)) * 100).toFixed(0);
    const symbol = r.failed === 0 ? "+" : r.passed > 0 ? "~" : "x";
    console.log(`  [${symbol}] ${r.name}: ${r.passed}/${r.passed + r.failed} (${pct}%)${r.details.length > 0 ? " — " + r.details.join("; ") : ""}`);
  }

  const allPassed = results.filter((r) => r.failed === 0).length;
  console.log(`\n  ${allPassed}/${results.length} models passed ALL challenges.\n`);
}

main().catch((err) => {
  console.error(`\n  Fatal: ${err.message}\n`);
  process.exit(1);
});
