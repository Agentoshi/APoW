// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {AgentCoin} from "../src/AgentCoin.sol";
import {IMiningAgent} from "../src/interfaces/IMiningAgent.sol";

contract MockMinerSim is ERC721, IMiningAgent {
    mapping(uint256 => uint16) public override hashpower;

    constructor() ERC721("Mock Miner Sim", "MSIM") {}

    function mint(address to, uint256 tokenId, uint16 hp) external {
        hashpower[tokenId] = hp;
        _mint(to, tokenId);
    }
}

/// @notice Full lifecycle emission simulation.
/// Validates tokenomics, era boundaries, difficulty adjustment, and gas profiling.
contract SimulationTest is Test {
    AgentCoin internal ac;
    MockMinerSim internal ma;

    address internal miner = makeAddr("miner");
    address internal lpVault = makeAddr("lpVault");

    bytes32 internal constant SLOT_TOTAL_MINES = bytes32(uint256(6));
    bytes32 internal constant SLOT_MINING_TARGET = bytes32(uint256(8));
    bytes32 internal constant SLOT_LAST_MINE_BLOCK = bytes32(uint256(9));
    bytes32 internal constant SLOT_LAST_ADJ_BLOCK = bytes32(uint256(10));
    bytes32 internal constant SLOT_MINES_SINCE_ADJ = bytes32(uint256(11));
    bytes32 internal constant SLOT_TOTAL_MINTED = bytes32(uint256(12));

    function setUp() public {
        ma = new MockMinerSim();
        ac = new AgentCoin(address(ma), lpVault);

        ma.mint(miner, 1, 100);  // Common (1.0x)
        ma.mint(miner, 2, 500);  // Mythic (5.0x)

        // Easy target for non-difficulty tests
        vm.store(address(ac), SLOT_MINING_TARGET, bytes32(type(uint256).max));
    }

    // ============ Mathematical Emission Verification ============

    function testSimulation_TotalEmission_CommonMiner() public view {
        uint256 totalTokens;
        uint256 baseReward = 3e18;
        uint256 eraCount;

        while (baseReward > 0) {
            uint256 minesThisEra = 500_000;
            totalTokens += minesThisEra * baseReward;
            eraCount++;
            baseReward = (baseReward * 90) / 100;
        }

        console.log("Eras until zero reward (Common):", eraCount);
        console.log("Total tokens if all 1.0x (Common):", totalTokens / 1e18, "AGENT");
        console.log("MINEABLE_SUPPLY:", ac.MINEABLE_SUPPLY() / 1e18, "AGENT");

        assertTrue(eraCount > 0, "Should have at least one era");
    }

    function testSimulation_TotalEmission_MythicMiner() public view {
        uint256 totalTokens;
        uint256 baseReward = 3e18;
        uint256 eraCount;

        while (baseReward > 0) {
            uint256 mythicReward = (baseReward * 500) / 100;
            uint256 minesThisEra = 500_000;
            totalTokens += minesThisEra * mythicReward;
            eraCount++;
            baseReward = (baseReward * 90) / 100;
        }

        console.log("Eras until zero reward (Mythic):", eraCount);
        console.log("Total tokens if all 5.0x (Mythic):", totalTokens / 1e18, "AGENT");

        assertTrue(eraCount > 0);
    }

    function testSimulation_ExactZeroCrossoverEra() public view {
        uint256 baseReward = 3e18;
        uint256 era;

        while (baseReward > 0) {
            era++;
            baseReward = (baseReward * 90) / 100;
        }

        console.log("Zero crossover at era:", era);
        assertTrue(era >= 300 && era <= 500, "Zero crossover should be in reasonable range");
    }

    function testSimulation_RewardNeverUnderflows() public view {
        uint256 baseReward = 3e18;
        uint256 prevReward = baseReward;

        for (uint256 era = 0; era < 1000; ++era) {
            assertTrue(baseReward <= prevReward, "Reward should never increase");
            prevReward = baseReward;
            baseReward = (baseReward * 90) / 100;
        }
    }

    // ============ Era Boundary Transition ============

    function testSimulation_EraBoundaryTransition() public {
        uint256 eraInterval = ac.ERA_INTERVAL();
        vm.store(address(ac), SLOT_TOTAL_MINES, bytes32(eraInterval - 1));

        vm.roll(100);
        uint256 reward0 = _mine(miner, 1);
        assertEq(ac.totalMines(), eraInterval);

        vm.roll(101);
        uint256 reward1 = _mine(miner, 1);

        assertEq(reward0, 3e18);
        assertEq(reward1, 2.7e18);

        console.log("Era 0 reward:", reward0);
        console.log("Era 1 reward:", reward1);
    }

    function testSimulation_EraBoundaryTransition_Mythic() public {
        uint256 eraInterval = ac.ERA_INTERVAL();
        vm.store(address(ac), SLOT_TOTAL_MINES, bytes32(eraInterval - 1));

        vm.roll(100);
        uint256 reward0 = _mine(miner, 2);
        vm.roll(101);
        uint256 reward1 = _mine(miner, 2);

        assertEq(reward0, 15e18);
        assertEq(reward1, 13.5e18);
    }

    // ============ 64-Mine Difficulty Adjustment Cycle ============

    function testSimulation_DifficultyAdjustment_StableRate() public {
        // Use target small enough that miningTarget * 640 won't overflow
        uint256 initialTarget = type(uint256).max >> 10;
        vm.store(address(ac), SLOT_MINING_TARGET, bytes32(initialTarget));
        vm.store(address(ac), SLOT_MINES_SINCE_ADJ, bytes32(uint256(63)));
        vm.store(address(ac), SLOT_LAST_ADJ_BLOCK, bytes32(uint256(100)));
        vm.store(address(ac), SLOT_LAST_MINE_BLOCK, bytes32(uint256(419))); // 100 + 320 - 1

        vm.roll(420); // block 420 = 100 + 320
        _mineWithNonceSearch(miner, 1, initialTarget);

        uint256 targetAfter = ac.miningTarget();
        // At exact rate (320/320): target should be unchanged
        assertEq(targetAfter, initialTarget, "Target unchanged at exact expected rate");

        console.log("Initial target:", initialTarget);
        console.log("Target after stable mines:", targetAfter);
    }

    function testSimulation_DifficultyAdjustment_FastMining() public {
        uint256 initialTarget = type(uint256).max >> 10;
        vm.store(address(ac), SLOT_MINING_TARGET, bytes32(initialTarget));
        vm.store(address(ac), SLOT_MINES_SINCE_ADJ, bytes32(uint256(63)));
        vm.store(address(ac), SLOT_LAST_ADJ_BLOCK, bytes32(uint256(100)));
        vm.store(address(ac), SLOT_LAST_MINE_BLOCK, bytes32(uint256(163))); // 63 blocks

        vm.roll(164);
        _mineWithNonceSearch(miner, 1, initialTarget);

        uint256 targetAfter = ac.miningTarget();
        assertTrue(targetAfter < initialTarget, "Target should decrease (harder) with fast mining");

        // Fast mining clamped to expectedBlocks/2 = 160
        // adjustedTarget = initialTarget * 160 / 320 = initialTarget / 2
        assertEq(targetAfter, initialTarget / 2, "Should clamp to 0.5x");

        console.log("Target after fast mining:", targetAfter);
    }

    function testSimulation_DifficultyAdjustment_SlowMining() public {
        uint256 initialTarget = type(uint256).max >> 10;
        vm.store(address(ac), SLOT_MINING_TARGET, bytes32(initialTarget));
        vm.store(address(ac), SLOT_MINES_SINCE_ADJ, bytes32(uint256(63)));
        vm.store(address(ac), SLOT_LAST_ADJ_BLOCK, bytes32(uint256(100)));
        vm.store(address(ac), SLOT_LAST_MINE_BLOCK, bytes32(uint256(1379))); // 1280 blocks

        vm.roll(1380);
        _mineWithNonceSearch(miner, 1, initialTarget);

        uint256 targetAfter = ac.miningTarget();
        assertTrue(targetAfter > initialTarget, "Target should increase (easier) with slow mining");

        // Slow mining clamped to expectedBlocks*2 = 640
        // adjustedTarget = initialTarget * 640 / 320 = initialTarget * 2
        assertEq(targetAfter, initialTarget * 2, "Should clamp to 2x");

        console.log("Target after slow mining:", targetAfter);
    }

    // ============ Gas Profiling at High Eras ============

    function testSimulation_GasProfile_Era0() public {
        vm.roll(100);

        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(miner, miner);
        uint256 gasBefore = gasleft();
        ac.mine(0, sol, 1);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for mine() at era 0:", gasUsed);
        assertTrue(gasUsed < 200_000, "mine() should stay under 200k gas");
    }

    function testSimulation_GasProfile_Era100() public {
        vm.store(address(ac), SLOT_TOTAL_MINES, bytes32(uint256(100 * 500_000)));
        vm.roll(100);

        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(miner, miner);
        uint256 gasBefore = gasleft();
        ac.mine(0, sol, 1);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for mine() at era 100:", gasUsed);
        assertTrue(gasUsed < 300_000, "mine() at era 100 should stay under 300k gas");
    }

    function testSimulation_GasProfile_Era200() public {
        vm.store(address(ac), SLOT_TOTAL_MINES, bytes32(uint256(200 * 500_000)));
        vm.roll(100);

        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(miner, miner);
        uint256 gasBefore = gasleft();
        ac.mine(0, sol, 1);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for mine() at era 200:", gasUsed);
        assertTrue(gasUsed < 400_000, "mine() at era 200 should stay under 400k gas");
    }

    function testSimulation_GasProfile_NearZeroCrossover() public {
        vm.store(address(ac), SLOT_TOTAL_MINES, bytes32(uint256(398 * 500_000)));
        vm.roll(100);

        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(miner, miner);
        uint256 gasBefore = gasleft();
        ac.mine(0, sol, 1);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for mine() near zero crossover:", gasUsed);
    }

    // ============ Supply Exhaustion Edge Cases ============

    function testSimulation_SupplyCap_EnforcedCorrectly() public {
        uint256 mineable = ac.MINEABLE_SUPPLY();
        vm.store(address(ac), SLOT_TOTAL_MINTED, bytes32(mineable - 3e18));

        vm.roll(100);
        _mine(miner, 1);
        assertEq(ac.totalMinted(), mineable);

        vm.roll(101);
        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(miner, miner);
        vm.expectRevert("Supply exhausted");
        ac.mine(0, sol, 1);
    }

    function testSimulation_ZeroRewardMine_AtHighEra() public {
        vm.store(address(ac), SLOT_TOTAL_MINES, bytes32(uint256(500_000_000)));
        vm.roll(100);
        uint256 balBefore = ac.balanceOf(miner);
        _mine(miner, 1);
        uint256 balAfter = ac.balanceOf(miner);
        assertEq(balAfter - balBefore, 0, "Zero reward at high era");
    }

    // ============ Helpers ============

    function _mine(address _miner, uint256 tokenId) internal returns (uint256 reward) {
        uint256 balBefore = ac.balanceOf(_miner);

        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(_miner, _miner);
        ac.mine(0, sol, tokenId);

        reward = ac.balanceOf(_miner) - balBefore;
    }

    function _mineWithNonceSearch(address _miner, uint256 tokenId, uint256 target) internal {
        (bytes32 challenge, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);
        uint256 nonce = _findNonce(challenge, _miner, target);

        vm.prank(_miner, _miner);
        ac.mine(nonce, sol, tokenId);
    }

    function _findNonce(bytes32 challengeNumber, address _miner, uint256 target) internal pure returns (uint256) {
        for (uint256 i = 0; i < 100_000_000; ++i) {
            uint256 digest = uint256(keccak256(abi.encodePacked(challengeNumber, _miner, i)));
            if (digest < target) return i;
        }
        revert("No nonce found");
    }

    function _solveChallenge(AgentCoin.SMHLChallenge memory c) internal pure returns (string memory) {
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

        require(spacesPlaced == spacesNeeded, "Cannot place spaces");

        uint256 currentSum;
        for (uint256 i = 0; i < c.firstNChars; ++i) {
            if (isSpace[i]) {
                currentSum += 32;
            } else if (i == c.charPosition) {
                currentSum += c.charValue;
            } else {
                solution[i] = bytes1(uint8(33));
                currentSum += 33;
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

        require(remaining == 0, "Unsolvable challenge");

        if (!isSpace[c.charPosition]) {
            solution[c.charPosition] = bytes1(c.charValue);
        }

        return string(solution);
    }
}
