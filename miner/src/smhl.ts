import OpenAI from "openai";

import { config, requireLlmApiKey } from "./config";

export interface SmhlChallenge {
  targetAsciiSum: number;
  firstNChars: number;
  wordCount: number;
  charPosition: number;
  charValue: number;
  totalLength: number;
}

export function normalizeSmhlChallenge(raw: unknown): SmhlChallenge {
  if (Array.isArray(raw)) {
    const [targetAsciiSum, firstNChars, wordCount, charPosition, charValue, totalLength] = raw;
    return {
      targetAsciiSum: Number(targetAsciiSum),
      firstNChars: Number(firstNChars),
      wordCount: Number(wordCount),
      charPosition: Number(charPosition),
      charValue: Number(charValue),
      totalLength: Number(totalLength),
    };
  }

  if (raw && typeof raw === "object") {
    const challenge = raw as Record<string, unknown>;
    return {
      targetAsciiSum: Number(challenge.targetAsciiSum),
      firstNChars: Number(challenge.firstNChars),
      wordCount: Number(challenge.wordCount),
      charPosition: Number(challenge.charPosition),
      charValue: Number(challenge.charValue),
      totalLength: Number(challenge.totalLength),
    };
  }

  throw new Error("Unable to normalize SMHL challenge.");
}

export function buildSmhlPrompt(challenge: SmhlChallenge): string {
  const requiredChar = String.fromCharCode(challenge.charValue);
  return [
    "Generate a string that satisfies ALL of these constraints:",
    `- Total length: exactly ${challenge.totalLength} characters`,
    `- Exactly ${challenge.wordCount} words (separated by single spaces)`,
    `- Character at position ${challenge.charPosition} must be '${requiredChar}' (ASCII ${challenge.charValue})`,
    `- Sum of ASCII values of the first ${challenge.firstNChars} characters must equal ${challenge.targetAsciiSum}`,
    "- Use printable ASCII characters only.",
    "Return ONLY the string, nothing else.",
  ].join("\n");
}

export function validateSmhlSolution(solution: string, challenge: SmhlChallenge): string[] {
  const issues: string[] = [];

  if (!solution) {
    issues.push("empty response");
    return issues;
  }

  if (Buffer.byteLength(solution, "utf8") !== challenge.totalLength) {
    issues.push(
      `length ${Buffer.byteLength(solution, "utf8")} != ${challenge.totalLength}`,
    );
  }

  if (!/^[\x20-\x7E]+$/.test(solution)) {
    issues.push("solution must use printable ASCII only");
  }

  const words = solution.split(" ");
  if (words.length !== challenge.wordCount || words.some((word) => word.length === 0)) {
    issues.push(`word count ${words.filter(Boolean).length} != ${challenge.wordCount}`);
  }

  const actualCharCode = solution.charCodeAt(challenge.charPosition);
  if (actualCharCode !== challenge.charValue) {
    issues.push(`char code ${actualCharCode} != ${challenge.charValue}`);
  }

  let asciiSum = 0;
  for (let index = 0; index < challenge.firstNChars; index += 1) {
    asciiSum += solution.charCodeAt(index);
  }
  if (asciiSum !== challenge.targetAsciiSum) {
    issues.push(`ASCII sum ${asciiSum} != ${challenge.targetAsciiSum}`);
  }

  return issues;
}

function sanitizeResponse(text: string): string {
  let cleaned = text.replace(/\r/g, "").trim();

  const fenceMatch = cleaned.match(/^```(?:text)?\n([\s\S]*?)\n```$/);
  if (fenceMatch) {
    cleaned = fenceMatch[1];
  }

  if (
    (cleaned.startsWith('"') && cleaned.endsWith('"')) ||
    (cleaned.startsWith("'") && cleaned.endsWith("'"))
  ) {
    cleaned = cleaned.slice(1, -1);
  }

  return cleaned;
}

async function requestOpenAiSolution(prompt: string): Promise<string> {
  const client = new OpenAI({ apiKey: requireLlmApiKey() });
  const response = await client.chat.completions.create({
    model: config.llmModel,
    temperature: 0,
    messages: [
      {
        role: "system",
        content:
          "You solve constrained ASCII string generation tasks. Return only the exact string requested.",
      },
      { role: "user", content: prompt },
    ],
  });

  return response.choices[0]?.message.content ?? "";
}

async function requestAnthropicSolution(prompt: string): Promise<string> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": requireLlmApiKey(),
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: config.llmModel,
      max_tokens: 200,
      temperature: 0,
      system:
        "You solve constrained ASCII string generation tasks. Return only the exact string requested.",
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!response.ok) {
    throw new Error(`Anthropic request failed: ${response.status} ${response.statusText}`);
  }

  const data = (await response.json()) as {
    content?: Array<{ type: string; text?: string }>;
  };

  return data.content?.find((item) => item.type === "text")?.text ?? "";
}

async function requestOllamaSolution(prompt: string): Promise<string> {
  const response = await fetch("http://127.0.0.1:11434/api/generate", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model: config.llmModel,
      prompt: [
        "You solve constrained ASCII string generation tasks.",
        "Return only the exact string requested.",
        "",
        prompt,
      ].join("\n"),
      stream: false,
      options: { temperature: 0 },
    }),
  });

  if (!response.ok) {
    throw new Error(`Ollama request failed: ${response.status} ${response.statusText}`);
  }

  const data = (await response.json()) as { response?: string };
  return data.response ?? "";
}

async function requestProviderSolution(prompt: string): Promise<string> {
  switch (config.llmProvider) {
    case "anthropic":
      return requestAnthropicSolution(prompt);
    case "ollama":
      return requestOllamaSolution(prompt);
    case "openai":
    default:
      return requestOpenAiSolution(prompt);
  }
}

export async function solveSmhlChallenge(challenge: SmhlChallenge): Promise<string> {
  const prompt = buildSmhlPrompt(challenge);
  let lastIssues = "provider did not return a valid response";

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const raw = await requestProviderSolution(prompt);
    const candidate = sanitizeResponse(raw);
    const issues = validateSmhlSolution(candidate, challenge);

    if (issues.length === 0) {
      return candidate;
    }

    lastIssues = `attempt ${attempt}: ${issues.join(", ")}`;
  }

  throw new Error(`SMHL solve failed after 3 attempts: ${lastIssues}`);
}
