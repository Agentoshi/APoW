// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Test} from "forge-std/Test.sol";

import {AgentCoin} from "../src/AgentCoin.sol";
import {IMiningAgent} from "../src/interfaces/IMiningAgent.sol";

contract MockMiningAgent is ERC721, IMiningAgent {
    mapping(uint256 => uint16) public override hashpower;

    constructor() ERC721("Mock Mining Agent", "MMINER") {}

    function mint(address to, uint256 tokenId, uint16 hp) external {
        hashpower[tokenId] = hp;
        _mint(to, tokenId);
    }
}

contract AgentCoinTest is Test {
    AgentCoin internal agentCoin;
    MockMiningAgent internal miningAgent;

    address internal user = makeAddr("user");
    address internal otherUser = makeAddr("otherUser");
    address internal lpVault = makeAddr("lpVault");

    // Storage slots from `forge inspect AgentCoin storage-layout`
    bytes32 internal constant SLOT_TOTAL_MINES = bytes32(uint256(6));
    bytes32 internal constant SLOT_MINING_TARGET = bytes32(uint256(8));

    function setUp() public {
        miningAgent = new MockMiningAgent();
        agentCoin = new AgentCoin(address(miningAgent), lpVault);

        miningAgent.mint(user, 1, 100);
        miningAgent.mint(user, 2, 500);
        miningAgent.mint(otherUser, 3, 100);
    }

    function testMineWithDualProof() public {
        _setMiningTarget(type(uint256).max);
        vm.roll(block.number + 1);

        uint256 reward = _mine(user, 1, 0);

        assertEq(reward, 3e18); // BASE_REWARD=3, Common hp=100 → 3*100/100=3
        assertEq(agentCoin.balanceOf(user), reward);
        assertEq(agentCoin.totalMines(), 1);
        assertEq(agentCoin.totalMinted(), reward);
        assertEq(agentCoin.tokenMineCount(1), 1);
        assertEq(agentCoin.tokenEarnings(1), reward);
    }

    function testMineInvalidHash() public {
        _setMiningTarget(0);
        vm.roll(block.number + 1);

        (, , AgentCoin.SMHLChallenge memory challenge) = agentCoin.getMiningChallenge();
        string memory solution = _solveChallenge(challenge);

        vm.prank(user, user);
        vm.expectRevert("Invalid hash");
        agentCoin.mine(0, solution, 1);
    }

    function testMineWithoutNFT() public {
        _setMiningTarget(type(uint256).max);
        vm.roll(block.number + 1);

        (, , AgentCoin.SMHLChallenge memory challenge) = agentCoin.getMiningChallenge();
        string memory solution = _solveChallenge(challenge);

        vm.prank(user, user);
        vm.expectRevert("Not your miner");
        agentCoin.mine(0, solution, 3);
    }

    function testHashpowerMultiplier() public {
        _setMiningTarget(type(uint256).max);

        vm.roll(100);
        uint256 commonReward = _mine(user, 1, 0);
        assertEq(commonReward, 3e18); // 3*100/100

        vm.roll(101);
        uint256 mythicReward = _mine(user, 2, 1);
        assertEq(mythicReward, 15e18); // 3*500/100
        assertEq(agentCoin.balanceOf(user), commonReward + mythicReward);
    }

    function testBlockGuard() public {
        _setMiningTarget(type(uint256).max);
        vm.roll(block.number + 1);

        _mine(user, 1, 0);

        (, , AgentCoin.SMHLChallenge memory challenge) = agentCoin.getMiningChallenge();
        string memory solution = _solveChallenge(challenge);

        vm.prank(user, user);
        vm.expectRevert("One mine per block");
        agentCoin.mine(1, solution, 1);
    }

    function testChallengeRotation() public {
        _setMiningTarget(type(uint256).max);
        bytes32 initialChallenge = agentCoin.challengeNumber();

        vm.roll(block.number + 1);
        _mine(user, 1, 0);

        assertTrue(agentCoin.challengeNumber() != initialChallenge);
    }

    function testEraDecay() public {
        _setMiningTarget(type(uint256).max);
        vm.store(address(agentCoin), SLOT_TOTAL_MINES, bytes32(agentCoin.ERA_INTERVAL() - 1));

        vm.roll(100);
        uint256 firstReward = _mine(user, 1, 0);
        assertEq(firstReward, 3e18); // Era 0: 3 AGENT (Common)

        vm.roll(101);
        uint256 secondReward = _mine(user, 1, 1);
        assertEq(secondReward, 2.7e18); // Era 1: 3 * 90/100 = 2.7 AGENT
        assertEq(agentCoin.balanceOf(user), firstReward + secondReward);
    }

    function _mine(address miner, uint256 tokenId, uint256 nonce) internal returns (uint256 reward) {
        (, , AgentCoin.SMHLChallenge memory challenge) = agentCoin.getMiningChallenge();
        string memory solution = _solveChallenge(challenge);
        reward = _expectedReward(tokenId);

        vm.prank(miner, miner);
        agentCoin.mine(nonce, solution, tokenId);
    }

    function _expectedReward(uint256 tokenId) internal view returns (uint256) {
        uint256 era = agentCoin.totalMines() / agentCoin.ERA_INTERVAL();
        uint256 baseReward = agentCoin.BASE_REWARD();
        for (uint256 i = 0; i < era; ++i) {
            baseReward = (baseReward * agentCoin.REWARD_DECAY_NUM()) / agentCoin.REWARD_DECAY_DEN();
        }
        return (baseReward * miningAgent.hashpower(tokenId)) / 100;
    }

    function _setMiningTarget(uint256 target) internal {
        vm.store(address(agentCoin), SLOT_MINING_TARGET, bytes32(target));
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
                    || (cursor > 0 && isSpace[cursor - 1]) || (cursor + 1 < challenge.totalLength && isSpace[cursor + 1])
            ) {
                unchecked {
                    --cursor;
                }
            }
            solution[cursor] = bytes1(uint8(32));
            isSpace[cursor] = true;
            if (cursor > 1) {
                cursor -= 2;
            }
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
            if (i == challenge.charPosition) {
                continue;
            }

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
}
