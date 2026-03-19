/**
 * SMHL Stress Test
 *
 * Generates N random SMHL challenges (varying seeds) and tests solve rate
 * against the configured LLM. No on-chain interaction needed.
 *
 * Usage:
 *   LLM_PROVIDER=gemini LLM_API_KEY=$GEMINI_API_KEY LLM_MODEL=gemini-2.5-flash \
 *     npx tsx stress-test.ts [count=50] [concurrency=5]
 */

import { hexToBytes, toHex, keccak256, encodePacked } from "viem";
import { normalizeSmhlChallenge, solveSmhlChallenge, validateSmhlSolution, buildSmhlPrompt, type SmhlChallenge } from "./src/smhl";

const COUNT = parseInt(process.argv[2] || "50", 10);
const CONCURRENCY = parseInt(process.argv[3] || "5", 10);

interface ChallengeResult {
  seed: string;
  challenge: SmhlChallenge;
  solved: boolean;
  attempts: number;
  elapsed: number;
  error?: string;
  failureMode?: string;
}

function generateRandomSeed(index: number): `0x${string}` {
  // Generate deterministic but varied seeds by hashing the index
  return keccak256(encodePacked(["uint256", "string"], [BigInt(index), "stress-test-seed"]));
}

function deriveChallengeFromSeed(seed: `0x${string}`): SmhlChallenge {
  const bytes = hexToBytes(seed);
  const firstNChars = 5 + (bytes[0] % 6);
  const wordCount = 3 + (bytes[2] % 5);
  const totalLength = 20 + (bytes[5] % 31);
  const charPosition = bytes[3] % totalLength;
  const charValue = 97 + (bytes[4] % 26);

  let targetAsciiSum = 400 + (bytes[1] * 3);
  let maxAsciiSum = firstNChars * 126;
  if (charPosition < firstNChars) {
    maxAsciiSum = maxAsciiSum - 126 + charValue;
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

function analyzeDifficulty(c: SmhlChallenge): { avgCharNeeded: number; feasible: boolean; tight: boolean } {
  const avgCharNeeded = c.targetAsciiSum / c.firstNChars;
  // printable ASCII is 32-126, avg ~79
  const feasible = avgCharNeeded >= 32 && avgCharNeeded <= 126;
  // "tight" = the model needs very specific high or low chars
  const tight = avgCharNeeded > 110 || avgCharNeeded < 50;
  return { avgCharNeeded, feasible, tight };
}

async function testChallenge(index: number): Promise<ChallengeResult> {
  const seed = generateRandomSeed(index);
  const challenge = deriveChallengeFromSeed(seed);
  const start = Date.now();

  try {
    const solution = await solveSmhlChallenge(challenge);
    return {
      seed,
      challenge,
      solved: true,
      attempts: 1, // solveSmhlChallenge retries internally up to 3
      elapsed: Date.now() - start,
    };
  } catch (err) {
    const elapsed = Date.now() - start;
    const error = err instanceof Error ? err.message : String(err);

    // Analyze failure mode
    let failureMode = "unknown";
    if (error.includes("length")) failureMode = "wrong_length";
    else if (error.includes("word count")) failureMode = "wrong_word_count";
    else if (error.includes("ASCII sum")) failureMode = "wrong_ascii_sum";
    else if (error.includes("char code")) failureMode = "wrong_char_position";
    else if (error.includes("printable")) failureMode = "non_printable";
    else if (error.includes("empty")) failureMode = "empty_response";
    else failureMode = "multi_constraint";

    return {
      seed,
      challenge,
      solved: false,
      attempts: 3,
      elapsed,
      error,
      failureMode,
    };
  }
}

async function runBatch(indices: number[]): Promise<ChallengeResult[]> {
  const results: ChallengeResult[] = [];
  for (let i = 0; i < indices.length; i += CONCURRENCY) {
    const batch = indices.slice(i, i + CONCURRENCY);
    const batchResults = await Promise.all(batch.map(testChallenge));
    results.push(...batchResults);

    const done = results.length;
    const passed = results.filter(r => r.solved).length;
    const rate = ((passed / done) * 100).toFixed(1);
    process.stderr.write(`\r  Progress: ${done}/${COUNT} | Pass rate: ${rate}% (${passed}/${done})`);
  }
  process.stderr.write("\n");
  return results;
}

async function main() {
  console.log(`\n  SMHL Stress Test`);
  console.log(`  ================`);
  console.log(`  Challenges: ${COUNT}`);
  console.log(`  Concurrency: ${CONCURRENCY}`);
  console.log(`  Provider: ${process.env.LLM_PROVIDER || "openai"}`);
  console.log(`  Model: ${process.env.LLM_MODEL || "gpt-4o-mini"}`);
  console.log("");

  // Pre-analyze challenge difficulty distribution
  const challenges: SmhlChallenge[] = [];
  for (let i = 0; i < COUNT; i++) {
    challenges.push(deriveChallengeFromSeed(generateRandomSeed(i)));
  }

  const difficulties = challenges.map(analyzeDifficulty);
  const tightCount = difficulties.filter(d => d.tight).length;
  const infeasibleCount = difficulties.filter(d => !d.feasible).length;

  console.log(`  Challenge distribution:`);
  console.log(`    Total length range: ${Math.min(...challenges.map(c => c.totalLength))}-${Math.max(...challenges.map(c => c.totalLength))}`);
  console.log(`    Word count range: ${Math.min(...challenges.map(c => c.wordCount))}-${Math.max(...challenges.map(c => c.wordCount))}`);
  console.log(`    First N chars range: ${Math.min(...challenges.map(c => c.firstNChars))}-${Math.max(...challenges.map(c => c.firstNChars))}`);
  console.log(`    ASCII sum range: ${Math.min(...challenges.map(c => c.targetAsciiSum))}-${Math.max(...challenges.map(c => c.targetAsciiSum))}`);
  console.log(`    Avg char needed range: ${Math.min(...difficulties.map(d => d.avgCharNeeded)).toFixed(1)}-${Math.max(...difficulties.map(d => d.avgCharNeeded)).toFixed(1)}`);
  console.log(`    Tight constraints: ${tightCount}/${COUNT} (${((tightCount/COUNT)*100).toFixed(0)}%)`);
  console.log(`    Infeasible: ${infeasibleCount}/${COUNT}`);
  console.log("");

  // Run tests
  const indices = Array.from({ length: COUNT }, (_, i) => i);
  const results = await runBatch(indices);

  // Results
  const passed = results.filter(r => r.solved);
  const failed = results.filter(r => !r.solved);
  const passRate = (passed.length / results.length) * 100;

  console.log(`\n  Results`);
  console.log(`  =======`);
  console.log(`  Pass rate: ${passRate.toFixed(1)}% (${passed.length}/${results.length})`);
  console.log(`  Avg solve time: ${(passed.reduce((s, r) => s + r.elapsed, 0) / Math.max(passed.length, 1) / 1000).toFixed(2)}s`);
  console.log(`  Avg fail time: ${(failed.reduce((s, r) => s + r.elapsed, 0) / Math.max(failed.length, 1) / 1000).toFixed(2)}s`);

  if (failed.length > 0) {
    // Failure mode breakdown
    const modes: Record<string, number> = {};
    for (const r of failed) {
      const mode = r.failureMode || "unknown";
      modes[mode] = (modes[mode] || 0) + 1;
    }

    console.log(`\n  Failure modes:`);
    for (const [mode, count] of Object.entries(modes).sort((a, b) => b[1] - a[1])) {
      console.log(`    ${mode}: ${count} (${((count / failed.length) * 100).toFixed(0)}%)`);
    }

    // Check if tight constraints correlate with failures
    const failedTight = failed.filter(r => analyzeDifficulty(r.challenge).tight).length;
    console.log(`\n  Tight constraint correlation:`);
    console.log(`    Failed + tight: ${failedTight}/${failed.length} (${((failedTight / failed.length) * 100).toFixed(0)}%)`);
    console.log(`    Overall tight: ${tightCount}/${COUNT} (${((tightCount / COUNT) * 100).toFixed(0)}%)`);
  }

  // Recommendation
  console.log(`\n  Assessment`);
  console.log(`  ==========`);
  if (passRate >= 90) {
    console.log(`  ✓ SMHL difficulty is appropriate. ${passRate.toFixed(0)}% solve rate is healthy.`);
  } else if (passRate >= 70) {
    console.log(`  ⚠ SMHL is moderately difficult. ${passRate.toFixed(0)}% rate means ~1 in ${Math.round(100/(100-passRate))} mines needs a retry.`);
    console.log(`    Consider: relax ASCII sum tolerance, reduce firstNChars range, or widen length range.`);
  } else if (passRate >= 40) {
    console.log(`  ✖ SMHL is too hard. ${passRate.toFixed(0)}% rate means most mines need multiple retries.`);
    console.log(`    Recommend: significantly relax constraints or reduce constraint count.`);
  } else {
    console.log(`  ✖✖ SMHL is broken for this model. ${passRate.toFixed(0)}% rate is unusable.`);
    console.log(`    Must: remove ASCII sum constraint, widen tolerances, or simplify to 2-3 constraints.`);
  }

  console.log("");
}

main().catch(console.error);
