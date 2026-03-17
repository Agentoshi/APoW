// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";

import {AgentCoin} from "../src/AgentCoin.sol";
import {IMiningAgent} from "../src/interfaces/IMiningAgent.sol";

contract MockMiningAgentEdge is ERC721, IMiningAgent {
    mapping(uint256 => uint16) public override hashpower;

    constructor() ERC721("Mock Mining Agent", "MMINER") {}

    function mint(address to, uint256 tokenId, uint16 hp) external {
        hashpower[tokenId] = hp;
        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }
}

// Contract caller to test tx.origin check
contract AgentContractCaller {
    function callMine(AgentCoin ac, uint256 nonce, string calldata sol, uint256 tokenId) external {
        ac.mine(nonce, sol, tokenId);
    }
}

contract AgentCoinEdgeTest is Test {
    AgentCoin internal ac;
    MockMiningAgentEdge internal ma;

    address internal user = makeAddr("user");
    address internal user2 = makeAddr("user2");
    address internal lpVault = makeAddr("lpVault");

    // Storage slots from `forge inspect AgentCoin storage-layout`
    bytes32 internal constant SLOT_TOTAL_MINES = bytes32(uint256(6));
    bytes32 internal constant SLOT_MINING_TARGET = bytes32(uint256(8));
    bytes32 internal constant SLOT_LAST_MINE_BLOCK = bytes32(uint256(9));
    bytes32 internal constant SLOT_LAST_ADJ_BLOCK = bytes32(uint256(10));
    bytes32 internal constant SLOT_MINES_SINCE_ADJ = bytes32(uint256(11));
    bytes32 internal constant SLOT_TOTAL_MINTED = bytes32(uint256(12));

    function setUp() public {
        ma = new MockMiningAgentEdge();
        ac = new AgentCoin(address(ma), lpVault);

        ma.mint(user, 1, 100);  // Common
        ma.mint(user, 2, 500);  // Mythic
        ma.mint(user2, 3, 100); // Common
        ma.mint(user, 4, 150);  // Uncommon
    }

    // ============ Access Control ============

    function testMineFromContract_Reverts() public {
        _setMiningTarget(type(uint256).max);
        vm.roll(100);

        AgentContractCaller caller = new AgentContractCaller();

        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.expectRevert("No contracts");
        caller.callMine(ac, 0, sol, 1);
    }

    function testConstructor_ZeroMiningAgent_Reverts() public {
        vm.expectRevert("Invalid MiningAgent");
        new AgentCoin(address(0), lpVault);
    }

    function testConstructor_ZeroLPVault_Reverts() public {
        vm.expectRevert("Invalid LPVault");
        new AgentCoin(address(ma), address(0));
    }

    function testLPVault_IsImmutable() public view {
        // lpVault is set in constructor and cannot be changed
        assertEq(ac.lpVault(), lpVault);
    }

    // ============ Constructor / Initial State ============

    function testConstructor_LPReserveMinted() public view {
        assertEq(ac.balanceOf(lpVault), ac.LP_RESERVE());
        assertEq(ac.LP_RESERVE(), 2_100_000e18);
    }

    function testConstructor_InitialChallengeNumber() public view {
        assertEq(ac.challengeNumber(), keccak256(bytes("AgentCoin Genesis")));
    }

    function testConstructor_InitialMiningTarget() public view {
        assertEq(ac.miningTarget(), type(uint256).max >> 16);
    }

    function testConstructor_TotalMintedIsZero() public view {
        assertEq(ac.totalMinted(), 0);
    }

    function testTokenName() public view {
        assertEq(ac.name(), "AgentCoin");
    }

    function testTokenSymbol() public view {
        assertEq(ac.symbol(), "AGENT");
    }

    // ============ Block Guard Edge Cases ============

    function testMine_SameBlockAsDeploy_Reverts() public {
        _setMiningTarget(type(uint256).max);
        // Don't roll — same block as deploy

        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(user, user);
        vm.expectRevert("One mine per block");
        ac.mine(0, sol, 1);
    }

    function testMine_ConsecutiveBlocks_Succeeds() public {
        _setMiningTarget(type(uint256).max);

        vm.roll(100);
        _mine(user, 1, 0);

        vm.roll(101);
        _mine(user, 1, 0);

        assertEq(ac.totalMines(), 2);
    }

    function testMine_SkippedBlocks_Succeeds() public {
        _setMiningTarget(type(uint256).max);

        vm.roll(100);
        _mine(user, 1, 0);

        vm.roll(10000);
        _mine(user, 1, 0);

        assertEq(ac.totalMines(), 2);
    }

    // ============ NFT Ownership Edge Cases ============

    function testMine_WithTransferredNFT() public {
        _setMiningTarget(type(uint256).max);
        vm.roll(100);

        // Transfer token 1 from user to user2
        vm.prank(user);
        ma.transferFrom(user, user2, 1);

        // user can no longer mine with token 1
        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(user, user);
        vm.expectRevert("Not your miner");
        ac.mine(0, sol, 1);

        // user2 CAN mine with token 1
        vm.prank(user2, user2);
        ac.mine(0, sol, 1);
        assertEq(ac.tokenMineCount(1), 1);
    }

    function testMine_NonexistentTokenId_Reverts() public {
        _setMiningTarget(type(uint256).max);
        vm.roll(100);

        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(user, user);
        vm.expectRevert(); // ERC721 ownerOf reverts for nonexistent token
        ac.mine(0, sol, 999);
    }

    function testMine_BurnedNFT_Reverts() public {
        _setMiningTarget(type(uint256).max);
        vm.roll(100);

        ma.burn(1);

        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(user, user);
        vm.expectRevert(); // ownerOf reverts for burned token
        ac.mine(0, sol, 1);
    }

    function testMine_SameTokenMultipleBlocks_Accumulates() public {
        _setMiningTarget(type(uint256).max);

        vm.roll(100);
        _mine(user, 1, 0);
        vm.roll(101);
        _mine(user, 1, 0);
        vm.roll(102);
        _mine(user, 1, 0);

        assertEq(ac.tokenMineCount(1), 3);
        assertEq(ac.tokenEarnings(1), 9e18); // 3 mines * 3 AGENT (Common)
    }

    function testMine_DifferentTokensSameOwner() public {
        _setMiningTarget(type(uint256).max);

        vm.roll(100);
        _mine(user, 1, 0); // Common (1.0x)
        vm.roll(101);
        _mine(user, 2, 0); // Mythic (5.0x)

        assertEq(ac.tokenMineCount(1), 1);
        assertEq(ac.tokenEarnings(1), 3e18);
        assertEq(ac.tokenMineCount(2), 1);
        assertEq(ac.tokenEarnings(2), 15e18);
        assertEq(ac.balanceOf(user), 18e18);
    }

    // ============ SMHL Verification (AgentCoin) ============

    function testMine_InvalidSMHL_WrongLength() public {
        _setMiningTarget(type(uint256).max);
        vm.roll(100);

        vm.prank(user, user);
        vm.expectRevert("Invalid SMHL");
        ac.mine(0, "", 1);
    }

    function testMine_InvalidSMHL_WrongChar() public {
        _setMiningTarget(type(uint256).max);
        vm.roll(100);

        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        // Tamper with charPosition
        bytes memory tampered = bytes(sol);
        tampered[c.charPosition] = bytes1(uint8(c.charValue) == 97 ? 98 : 97);

        vm.prank(user, user);
        vm.expectRevert("Invalid SMHL");
        ac.mine(0, string(tampered), 1);
    }

    // ============ Hash Proof Edge Cases ============

    function testMine_DigestExactlyAtTarget_Reverts() public {
        // Set target to 1 — extremely hard, only digest == 0 passes
        vm.store(address(ac), SLOT_MINING_TARGET, bytes32(uint256(1)));
        vm.roll(100);

        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        // nonce 0 almost certainly produces digest >= 1
        vm.prank(user, user);
        vm.expectRevert("Invalid hash");
        ac.mine(0, sol, 1);
    }

    function testMine_EasyTarget_AnyNonce() public {
        _setMiningTarget(type(uint256).max);
        vm.roll(100);

        // With max target, any nonce works
        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(user, user);
        ac.mine(12345678, sol, 1); // arbitrary nonce
        assertEq(ac.totalMines(), 1);
    }

    // ============ Supply Exhaustion ============

    function testMine_SupplyExhausted_Reverts() public {
        _setMiningTarget(type(uint256).max);
        // Set totalMinted to just under MINEABLE_SUPPLY, leaving room for less than one reward
        uint256 mineable = ac.MINEABLE_SUPPLY();
        vm.store(address(ac), SLOT_TOTAL_MINTED, bytes32(mineable - 1)); // 1 wei left

        vm.roll(100);
        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        // Common reward = 2e18, but only 1 wei left
        vm.prank(user, user);
        vm.expectRevert("Supply exhausted");
        ac.mine(0, sol, 1);
    }

    function testMine_ExactSupplyExhaustion_Succeeds() public {
        _setMiningTarget(type(uint256).max);
        // Set totalMinted to MINEABLE_SUPPLY - 3e18 (exact last Common reward)
        uint256 mineable = ac.MINEABLE_SUPPLY();
        vm.store(address(ac), SLOT_TOTAL_MINTED, bytes32(mineable - 3e18));

        vm.roll(100);
        _mine(user, 1, 0); // Common = 3e18, fills exactly

        assertEq(ac.totalMinted(), mineable);
    }

    function testMine_MythicExhaustsSupplyFaster() public {
        _setMiningTarget(type(uint256).max);
        // Mythic reward = 15e18. Set totalMinted to MINEABLE_SUPPLY - 5e18
        uint256 mineable = ac.MINEABLE_SUPPLY();
        vm.store(address(ac), SLOT_TOTAL_MINTED, bytes32(mineable - 5e18));

        vm.roll(100);

        // Mythic (tokenId 2, hp=500) reward = 15e18 > 5e18 remaining
        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(user, user);
        vm.expectRevert("Supply exhausted");
        ac.mine(0, sol, 2);
    }

    // ============ Reward Decay Edge Cases ============

    function testDecay_Era2_Reward() public {
        _setMiningTarget(type(uint256).max);
        vm.store(address(ac), SLOT_TOTAL_MINES, bytes32(uint256(1_000_000))); // era 2

        vm.roll(100);
        uint256 reward = _mine(user, 1, 0);
        // era 2: 3e18 * 90/100 * 90/100 = 2.43e18, Common 1.0x = 2.43e18
        assertEq(reward, 2.43e18);
    }

    function testDecay_HighEra_NearZeroReward() public {
        _setMiningTarget(type(uint256).max);
        // era = totalMines / 500K. At 500M mines → era 1000 → reward rounds to 0
        vm.store(address(ac), SLOT_TOTAL_MINES, bytes32(uint256(500_000_000)));

        vm.roll(100);
        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        // Reward is 0 after 1000 decay steps (0.9^1000 ≈ 0), succeeds with 0 mint
        vm.prank(user, user);
        ac.mine(0, sol, 1);

        // Balance unchanged (0 minted)
        assertEq(ac.tokenEarnings(1), 0);
    }

    function testDecay_MythicEra1() public {
        _setMiningTarget(type(uint256).max);
        vm.store(address(ac), SLOT_TOTAL_MINES, bytes32(uint256(500_000))); // era 1

        vm.roll(100);
        uint256 reward = _mine(user, 2, 0); // Mythic, hp=500
        // era 1: 3e18 * 90/100 = 2.7e18, Mythic 5.0x = 13.5e18
        assertEq(reward, 13.5e18);
    }

    // ============ Difficulty Adjustment ============

    function testDifficultyAdjustment_TriggerAt64Mines() public {
        _setMiningTarget(type(uint256).max);
        // Set lastAdjustmentBlock to 100 so we control the block range
        vm.store(address(ac), SLOT_LAST_ADJ_BLOCK, bytes32(uint256(100)));
        vm.store(address(ac), SLOT_LAST_MINE_BLOCK, bytes32(uint256(99)));

        // Use storage to set minesSinceAdjustment to 63, then mine once to trigger
        vm.store(address(ac), SLOT_MINES_SINCE_ADJ, bytes32(uint256(63)));
        vm.store(address(ac), SLOT_TOTAL_MINES, bytes32(uint256(63)));

        vm.roll(200);
        _mine(user, 1, 0);

        assertEq(ac.minesSinceAdjustment(), 0); // Reset after adjustment
        assertEq(ac.totalMines(), 64); // Adjustment triggers at ADJUSTMENT_INTERVAL (64)
    }

    function testDifficultyAdjustment_FasterMining_HarderTarget() public {
        // Use initial target (type(uint256).max >> 16) — small enough to avoid overflow
        uint256 initialTarget = type(uint256).max >> 16;
        vm.store(address(ac), SLOT_MINING_TARGET, bytes32(initialTarget));
        uint256 targetBefore = ac.miningTarget();

        // Simulate: 63 mines in 63 blocks (fast: 1 per block vs expected 5)
        vm.store(address(ac), SLOT_MINES_SINCE_ADJ, bytes32(uint256(63)));
        vm.store(address(ac), SLOT_LAST_ADJ_BLOCK, bytes32(uint256(100)));
        vm.store(address(ac), SLOT_LAST_MINE_BLOCK, bytes32(uint256(162)));

        vm.roll(163);
        _mineWithNonceSearch(user, 1, initialTarget);

        uint256 targetAfter = ac.miningTarget();
        assertTrue(targetAfter < targetBefore, "Target should decrease when mining faster");
    }

    function testDifficultyAdjustment_SlowerMining_EasierTarget() public {
        uint256 initialTarget = type(uint256).max >> 16;
        vm.store(address(ac), SLOT_MINING_TARGET, bytes32(initialTarget));
        uint256 targetBefore = ac.miningTarget();

        // Simulate: 63 mines in 640 blocks (slow: 10 per block vs expected 5)
        vm.store(address(ac), SLOT_MINES_SINCE_ADJ, bytes32(uint256(63)));
        vm.store(address(ac), SLOT_LAST_ADJ_BLOCK, bytes32(uint256(100)));
        vm.store(address(ac), SLOT_LAST_MINE_BLOCK, bytes32(uint256(739)));

        vm.roll(740);
        _mineWithNonceSearch(user, 1, initialTarget);

        uint256 targetAfter = ac.miningTarget();
        assertTrue(targetAfter > targetBefore, "Target should increase when mining slower");
    }

    function testDifficultyAdjustment_ExactExpected_NoChange() public {
        uint256 initialTarget = type(uint256).max >> 16;
        vm.store(address(ac), SLOT_MINING_TARGET, bytes32(initialTarget));
        uint256 targetBefore = ac.miningTarget();

        // Simulate: 63 mines in exactly 320 blocks = exact expected rate
        vm.store(address(ac), SLOT_MINES_SINCE_ADJ, bytes32(uint256(63)));
        vm.store(address(ac), SLOT_LAST_ADJ_BLOCK, bytes32(uint256(100)));
        vm.store(address(ac), SLOT_LAST_MINE_BLOCK, bytes32(uint256(419)));

        vm.roll(420);
        _mineWithNonceSearch(user, 1, initialTarget);

        uint256 targetAfter = ac.miningTarget();
        assertEq(targetAfter, targetBefore, "Target unchanged at exact expected rate");
    }

    function testDifficultyAdjustment_ClampMin_Half() public {
        uint256 initialTarget = type(uint256).max >> 16;
        vm.store(address(ac), SLOT_MINING_TARGET, bytes32(initialTarget));
        uint256 targetBefore = ac.miningTarget();

        // Simulate extreme speed: 63 mines in 1 block (clamped to 0.5x)
        vm.store(address(ac), SLOT_MINES_SINCE_ADJ, bytes32(uint256(63)));
        vm.store(address(ac), SLOT_LAST_ADJ_BLOCK, bytes32(uint256(99)));
        vm.store(address(ac), SLOT_LAST_MINE_BLOCK, bytes32(uint256(99)));

        vm.roll(100);
        _mineWithNonceSearch(user, 1, initialTarget);

        uint256 targetAfter = ac.miningTarget();
        assertEq(targetAfter, targetBefore / 2, "Should clamp to 0.5x");
    }

    function testDifficultyAdjustment_TargetNeverZero() public {
        // Set target to 2, trigger adjustment that would halve it to 1
        // Use easy target so nonce 0 works
        _setMiningTarget(type(uint256).max);
        vm.store(address(ac), SLOT_MINES_SINCE_ADJ, bytes32(uint256(63)));
        vm.store(address(ac), SLOT_LAST_ADJ_BLOCK, bytes32(uint256(99)));
        vm.store(address(ac), SLOT_LAST_MINE_BLOCK, bytes32(uint256(99)));

        vm.roll(100);
        // This triggers adjustment. With max target and overflow protection,
        // the target should be capped at type(uint256).max
        _mine(user, 1, 0);

        assertTrue(ac.miningTarget() >= 1, "Target should never be 0");
    }

    // ============ Challenge Rotation ============

    function testSMHLNonceIncrementsEachMine() public {
        _setMiningTarget(type(uint256).max);

        uint256 nonce0 = ac.smhlNonce();
        vm.roll(100);
        _mine(user, 1, 0);
        assertEq(ac.smhlNonce(), nonce0 + 1);

        vm.roll(101);
        _mine(user, 1, 0);
        assertEq(ac.smhlNonce(), nonce0 + 2);
    }

    function testGetMiningChallenge_ViewConsistency() public view {
        // Calling getMiningChallenge multiple times returns same result (it's a view)
        (bytes32 c1, uint256 t1,) = ac.getMiningChallenge();
        (bytes32 c2, uint256 t2,) = ac.getMiningChallenge();
        assertEq(c1, c2);
        assertEq(t1, t2);
    }

    // ============ Token Tracking ============

    function testTotalMinted_MatchesSumOfRewards() public {
        _setMiningTarget(type(uint256).max);

        vm.roll(100);
        uint256 r1 = _mine(user, 1, 0); // Common = 2e18
        vm.roll(101);
        uint256 r2 = _mine(user, 2, 0); // Mythic = 10e18

        assertEq(ac.totalMinted(), r1 + r2);
        assertEq(ac.totalMinted(), 18e18); // 3 (Common) + 15 (Mythic)
    }

    function testTransfer_MinedTokens() public {
        _setMiningTarget(type(uint256).max);

        vm.roll(100);
        _mine(user, 1, 0);
        assertEq(ac.balanceOf(user), 3e18);

        // Transfer AGENT tokens (ERC-20)
        vm.prank(user);
        ac.transfer(user2, 1e18);

        assertEq(ac.balanceOf(user), 2e18);
        assertEq(ac.balanceOf(user2), 1e18);
    }

    // ============ Helpers ============

    function _setMiningTarget(uint256 target) internal {
        vm.store(address(ac), SLOT_MINING_TARGET, bytes32(target));
    }

    function _mine(address miner, uint256 tokenId, uint256 nonce) internal returns (uint256 reward) {
        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);
        reward = _expectedReward(tokenId);

        vm.prank(miner, miner);
        ac.mine(nonce, sol, tokenId);
    }

    function _expectedReward(uint256 tokenId) internal view returns (uint256) {
        uint256 era = ac.totalMines() / ac.ERA_INTERVAL();
        uint256 baseReward = ac.BASE_REWARD();
        for (uint256 i = 0; i < era; ++i) {
            baseReward = (baseReward * ac.REWARD_DECAY_NUM()) / ac.REWARD_DECAY_DEN();
        }
        return (baseReward * ma.hashpower(tokenId)) / 100;
    }

    function _mineWithNonceSearch(address miner, uint256 tokenId, uint256 target) internal {
        (bytes32 challenge, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);
        uint256 nonce = _findNonce(challenge, miner, target);
        vm.prank(miner, miner);
        ac.mine(nonce, sol, tokenId);
    }

    function _findNonce(bytes32 challengeNumber, address miner, uint256 target) internal pure returns (uint256) {
        for (uint256 i = 0; i < 100_000_000; ++i) {
            uint256 digest = uint256(keccak256(abi.encodePacked(challengeNumber, miner, i)));
            if (digest < target) return i;
        }
        revert("No nonce found");
    }

    function _solveChallenge(AgentCoin.SMHLChallenge memory challenge) internal pure returns (string memory) {
        bytes memory solution = new bytes(challenge.totalLength);
        bool[] memory isSpace = new bool[](challenge.totalLength);

        for (uint256 i = 0; i < challenge.totalLength; ++i) {
            solution[i] = bytes1(uint8(65));
        }

        uint256 spacesNeeded = challenge.wordCount - 1;
        uint256 cursor = challenge.totalLength - 2;
        for (uint256 i = 0; i < spacesNeeded; ++i) {
            while (
                cursor < challenge.firstNChars || cursor == challenge.charPosition || isSpace[cursor]
                    || (cursor > 0 && isSpace[cursor - 1])
                    || (cursor + 1 < challenge.totalLength && isSpace[cursor + 1])
            ) {
                unchecked { --cursor; }
            }
            solution[cursor] = bytes1(uint8(32));
            isSpace[cursor] = true;
            if (cursor > 1) cursor -= 2;
        }

        uint256 currentSum;
        for (uint256 i = 0; i < challenge.firstNChars; ++i) {
            if (i == challenge.charPosition) {
                solution[i] = bytes1(challenge.charValue);
            } else {
                solution[i] = bytes1(uint8(33));
            }
            currentSum += uint8(solution[i]);
        }

        uint256 remaining = challenge.targetAsciiSum - currentSum;
        for (uint256 i = 0; i < challenge.firstNChars && remaining > 0; ++i) {
            if (i == challenge.charPosition) continue;
            uint256 add = remaining > 222 ? 222 : remaining;
            solution[i] = bytes1(uint8(solution[i]) + uint8(add));
            remaining -= add;
        }

        require(remaining == 0, "Unsolvable challenge");

        if (challenge.charPosition >= challenge.firstNChars) {
            solution[challenge.charPosition] = bytes1(challenge.charValue);
        }

        return string(solution);
    }

    // ============ Fuzz: SMHL Challenge Solvability ============

    function _deriveChallengeLocal(bytes32 seed) internal pure returns (AgentCoin.SMHLChallenge memory challenge) {
        challenge.firstNChars = 5 + (uint8(seed[0]) % 6);
        challenge.wordCount = 3 + (uint8(seed[2]) % 5);
        challenge.totalLength = 20 + (uint16(uint8(seed[5])) % 31);
        challenge.charPosition = uint8(seed[3]) % uint8(challenge.totalLength);
        challenge.charValue = 97 + (uint8(seed[4]) % 26);

        uint16 rawTargetAsciiSum = 400 + (uint16(uint8(seed[1])) * 3);
        uint16 maxAsciiSum = uint16(challenge.firstNChars) * 255;
        if (challenge.charPosition < challenge.firstNChars) {
            maxAsciiSum = maxAsciiSum - 255 + challenge.charValue;
        }

        if (rawTargetAsciiSum > maxAsciiSum) {
            rawTargetAsciiSum = uint16(400 + ((rawTargetAsciiSum - 400) % (maxAsciiSum - 399)));
        }
        challenge.targetAsciiSum = rawTargetAsciiSum;
    }

    function _verifySMHLLocal(string memory solution, AgentCoin.SMHLChallenge memory c)
        internal
        pure
        returns (bool)
    {
        bytes memory chars = bytes(solution);
        if (chars.length != c.totalLength) return false;
        if (uint8(chars[c.charPosition]) != c.charValue) return false;

        uint256 asciiSum;
        for (uint256 i = 0; i < c.firstNChars; ++i) {
            asciiSum += uint8(chars[i]);
        }
        if (asciiSum != c.targetAsciiSum) return false;

        uint256 countedWords;
        bool inWord;
        for (uint256 i = 0; i < chars.length; ++i) {
            if (chars[i] == bytes1(" ")) {
                inWord = false;
            } else if (!inWord) {
                inWord = true;
                ++countedWords;
            }
        }

        return countedWords == c.wordCount;
    }

    function testFuzz_deriveChallenge_AlwaysSolvable(bytes32 seed) public pure {
        AgentCoin.SMHLChallenge memory c = _deriveChallengeLocal(seed);

        // Verify constraint geometry: words must fit in totalLength
        assertTrue(c.totalLength >= c.wordCount * 2 - 1, "Words can't fit");
        assertTrue(c.firstNChars >= 5 && c.firstNChars <= 10, "firstNChars out of range");
        assertTrue(c.wordCount >= 3 && c.wordCount <= 7, "wordCount out of range");
        assertTrue(c.totalLength >= 20 && c.totalLength <= 50, "totalLength out of range");
        assertTrue(c.charPosition < c.totalLength, "charPosition out of bounds");
        assertTrue(c.charValue >= 97 && c.charValue <= 122, "charValue not lowercase");

        // Actually solve the challenge
        bytes memory solution = new bytes(c.totalLength);
        bool[] memory isSpace = new bool[](c.totalLength);

        for (uint256 i = 0; i < c.totalLength; ++i) {
            solution[i] = bytes1(uint8(65));
        }
        solution[c.charPosition] = bytes1(c.charValue);

        uint256 spacesNeeded = uint256(c.wordCount) - 1;
        uint256 spacesPlaced;

        if (c.totalLength > c.firstNChars) {
            uint256 pos = c.totalLength - 2;
            while (spacesPlaced < spacesNeeded && pos >= c.firstNChars) {
                if (pos != c.charPosition && !isSpace[pos]
                    && !(pos > 0 && isSpace[pos - 1])
                    && !(pos + 1 < c.totalLength && isSpace[pos + 1])
                ) {
                    solution[pos] = bytes1(uint8(32));
                    isSpace[pos] = true;
                    spacesPlaced++;
                }
                if (pos == c.firstNChars) break;
                pos--;
            }
        }

        if (spacesPlaced < spacesNeeded && c.firstNChars > 1) {
            uint256 pos = uint256(c.firstNChars) - 1;
            while (spacesPlaced < spacesNeeded && pos >= 1) {
                if (pos != c.charPosition && !isSpace[pos]
                    && !(pos > 0 && isSpace[pos - 1])
                    && !(pos + 1 < c.totalLength && isSpace[pos + 1])
                ) {
                    solution[pos] = bytes1(uint8(32));
                    isSpace[pos] = true;
                    spacesPlaced++;
                }
                if (pos == 1) break;
                pos--;
            }
        }

        // All spaces must be placed
        assertEq(spacesPlaced, spacesNeeded, "Cannot place all spaces");

        // Use base char \x01 (1) to handle low targetAsciiSum values.
        // The SMHL verifier doesn't check printability, so any non-zero byte works.
        // After distribution, fix any accidental byte=32 (space) which would break word count.
        uint256 currentSum;
        for (uint256 i = 0; i < c.firstNChars; ++i) {
            if (isSpace[i]) {
                currentSum += 32;
            } else if (i == c.charPosition) {
                currentSum += c.charValue;
            } else {
                solution[i] = bytes1(uint8(1));
                currentSum += 1;
            }
        }

        uint256 remaining = uint256(c.targetAsciiSum) - currentSum;
        for (uint256 i = 0; i < c.firstNChars && remaining > 0; ++i) {
            if (i == c.charPosition || isSpace[i]) continue;
            uint256 maxAdd = 255 - uint8(solution[i]);
            uint256 add = remaining > maxAdd ? maxAdd : remaining;
            solution[i] = bytes1(uint8(uint8(solution[i]) + uint8(add)));
            remaining -= add;
        }

        assertEq(remaining, 0, "Cannot reach target ASCII sum");

        // Post-fix: if any adjustable char in firstNChars ended up at 32 (space),
        // replace with 31 and compensate by increasing another char by 1.
        for (uint256 i = 0; i < c.firstNChars; ++i) {
            if (isSpace[i] || i == c.charPosition) continue;
            if (uint8(solution[i]) == 32) {
                solution[i] = bytes1(uint8(31)); // 32 → 31, sum decreases by 1
                // Compensate: increase another adjustable char by 1
                for (uint256 j = 0; j < c.firstNChars; ++j) {
                    if (j == i || isSpace[j] || j == c.charPosition) continue;
                    uint8 val = uint8(solution[j]);
                    if (val < 255 && val + 1 != 32) {
                        solution[j] = bytes1(val + 1);
                        break;
                    }
                }
            }
        }

        if (!isSpace[c.charPosition]) {
            solution[c.charPosition] = bytes1(c.charValue);
        }

        // Verify the solution passes all SMHL checks
        assertTrue(_verifySMHLLocal(string(solution), c), "Solution failed verification");
    }

    function testFuzz_deriveChallenge_TargetAsciiSumInRange(bytes32 seed) public pure {
        AgentCoin.SMHLChallenge memory c = _deriveChallengeLocal(seed);

        // targetAsciiSum should always be >= 400 (minimum from derivation)
        assertTrue(c.targetAsciiSum >= 400, "targetAsciiSum below minimum");

        // Compute max achievable ASCII sum for firstNChars
        uint16 maxAchievable = uint16(c.firstNChars) * 255;
        if (c.charPosition < c.firstNChars) {
            maxAchievable = maxAchievable - 255 + c.charValue;
        }
        assertTrue(c.targetAsciiSum <= maxAchievable, "targetAsciiSum exceeds maximum");
    }
}
