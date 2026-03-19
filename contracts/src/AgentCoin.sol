// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {IAgentCoin} from "./interfaces/IAgentCoin.sol";
import {IMiningAgent} from "./interfaces/IMiningAgent.sol";

contract AgentCoin is ERC20, Ownable, ReentrancyGuardTransient, IAgentCoin {
    uint256 public constant MAX_SUPPLY = 21_000_000e18;
    uint256 public constant LP_RESERVE = 2_100_000e18;
    uint256 public constant MINEABLE_SUPPLY = MAX_SUPPLY - LP_RESERVE;
    uint256 public constant BASE_REWARD = 3e18;
    uint256 public constant ERA_INTERVAL = 500_000;
    uint256 public constant REWARD_DECAY_NUM = 90;
    uint256 public constant REWARD_DECAY_DEN = 100;
    uint256 public constant ADJUSTMENT_INTERVAL = 64;
    uint256 public constant TARGET_BLOCK_INTERVAL = 5;
    uint256 public constant CHALLENGE_DURATION = 20;


    struct SMHLChallenge {
        uint16 targetAsciiSum;
        uint8 firstNChars;
        uint8 wordCount;
        uint8 charPosition;
        uint8 charValue;
        uint16 totalLength;
    }

    event Mined(address indexed miner, uint256 indexed tokenId, uint256 reward, uint256 totalMines);
    event DifficultyAdjusted(uint256 oldTarget, uint256 newTarget);

    IMiningAgent public immutable miningAgent;
    address public immutable lpVault;
    bool public lpDeployed;
    uint256 public totalMines;
    bytes32 public challengeNumber;
    uint256 public miningTarget;
    uint256 public lastMineBlockNumber;
    uint256 public lastAdjustmentBlock;
    uint256 public minesSinceAdjustment;
    uint256 public totalMinted;
    uint256 public smhlNonce;

    mapping(uint256 => uint256) public tokenMineCount;
    mapping(uint256 => uint256) public tokenEarnings;

    constructor(address _miningAgent, address _lpVault) ERC20("AgentCoin", "AGENT") Ownable(msg.sender) {
        require(_miningAgent != address(0), "Invalid MiningAgent");
        require(_lpVault != address(0), "Invalid LPVault");
        miningAgent = IMiningAgent(_miningAgent);
        lpVault = _lpVault;
        lpDeployed = false;

        challengeNumber = keccak256(bytes("AgentCoin Genesis"));
        miningTarget = type(uint256).max >> 16;
        lastMineBlockNumber = block.number;
        lastAdjustmentBlock = block.number;

        _mint(_lpVault, LP_RESERVE);
    }

    function setLPDeployed() external {
        require(msg.sender == lpVault, "Only LPVault");
        require(!lpDeployed, "Already set");
        lpDeployed = true;
    }

    function getMiningChallenge() external view returns (bytes32 challenge, uint256 target, SMHLChallenge memory smhl) {
        challenge = challengeNumber;
        target = miningTarget;
        smhl = _deriveChallenge(keccak256(abi.encodePacked(challengeNumber, smhlNonce)));
    }

    function mine(uint256 nonce, string calldata smhlSolution, uint256 tokenId) external nonReentrant {
        require(msg.sender == tx.origin, "No contracts");
        require(block.number > lastMineBlockNumber, "One mine per block");
        require(miningAgent.ownerOf(tokenId) == msg.sender, "Not your miner");

        SMHLChallenge memory challenge = _deriveChallenge(keccak256(abi.encodePacked(challengeNumber, smhlNonce)));
        require(_verifySMHL(smhlSolution, challenge), "Invalid SMHL");

        uint256 digest = uint256(keccak256(abi.encodePacked(challengeNumber, msg.sender, nonce)));
        require(digest < miningTarget, "Invalid hash");

        uint256 reward = _getReward(tokenId);
        require(totalMinted + reward <= MINEABLE_SUPPLY, "Supply exhausted");

        _mint(msg.sender, reward);

        totalMines += 1;
        totalMinted += reward;
        tokenMineCount[tokenId] += 1;
        tokenEarnings[tokenId] += reward;
        minesSinceAdjustment += 1;

        challengeNumber = keccak256(abi.encodePacked(challengeNumber, msg.sender, nonce, block.prevrandao));
        smhlNonce += 1;
        lastMineBlockNumber = block.number;

        emit Mined(msg.sender, tokenId, reward, totalMines);

        if (minesSinceAdjustment >= ADJUSTMENT_INTERVAL) {
            _adjustDifficulty();
        }
    }

    function _getReward(uint256 tokenId) internal view returns (uint256) {
        uint256 era = totalMines / ERA_INTERVAL;
        uint256 baseReward = BASE_REWARD;
        for (uint256 i = 0; i < era; ++i) {
            baseReward = (baseReward * REWARD_DECAY_NUM) / REWARD_DECAY_DEN;
        }
        return (baseReward * miningAgent.hashpower(tokenId)) / 100;
    }

    function _adjustDifficulty() internal {
        uint256 expectedBlocks = ADJUSTMENT_INTERVAL * TARGET_BLOCK_INTERVAL;
        uint256 actualBlocks = block.number - lastAdjustmentBlock;

        if (actualBlocks < expectedBlocks / 2) {
            actualBlocks = expectedBlocks / 2;
        } else if (actualBlocks > expectedBlocks * 2) {
            actualBlocks = expectedBlocks * 2;
        }

        uint256 adjustedTarget;
        if (miningTarget > type(uint256).max / actualBlocks) {
            adjustedTarget = type(uint256).max;
        } else {
            adjustedTarget = (miningTarget * actualBlocks) / expectedBlocks;
        }

        uint256 oldTarget = miningTarget;
        miningTarget = adjustedTarget == 0 ? 1 : adjustedTarget;
        lastAdjustmentBlock = block.number;
        minesSinceAdjustment = 0;

        emit DifficultyAdjusted(oldTarget, miningTarget);
    }

    function _deriveChallenge(bytes32 seed) internal pure returns (SMHLChallenge memory challenge) {
        challenge.firstNChars = 5 + (uint8(seed[0]) % 6);
        challenge.wordCount = 3 + (uint8(seed[2]) % 5);
        challenge.totalLength = 20 + (uint16(uint8(seed[5])) % 31);
        challenge.charPosition = uint8(seed[3]) % uint8(challenge.totalLength);
        challenge.charValue = 97 + (uint8(seed[4]) % 26);

        uint16 rawTargetAsciiSum = 400 + (uint16(uint8(seed[1])) * 3);
        uint16 maxAsciiSum = uint16(challenge.firstNChars) * 126;
        if (challenge.charPosition < challenge.firstNChars) {
            maxAsciiSum = maxAsciiSum - 126 + challenge.charValue;
        }

        if (rawTargetAsciiSum > maxAsciiSum) {
            rawTargetAsciiSum = uint16(400 + ((rawTargetAsciiSum - 400) % (maxAsciiSum - 399)));
        }
        challenge.targetAsciiSum = rawTargetAsciiSum;
    }

    function _verifySMHL(string calldata solution, SMHLChallenge memory c) internal pure returns (bool) {
        bytes calldata b = bytes(solution);
        uint256 len = b.length;

        // Length tolerance: ±5
        if (len + 5 < c.totalLength || len > uint256(c.totalLength) + 5) return false;

        bool hasChar;
        uint256 words;
        bool inWord;
        for (uint256 i = 0; i < len; ++i) {
            uint8 ch = uint8(b[i]);
            if (ch == c.charValue) hasChar = true;
            if (ch == 32) { inWord = false; }
            else if (!inWord) { inWord = true; ++words; }
        }
        if (!hasChar) return false;

        // Word count tolerance: ±2
        uint256 wdiff = words > c.wordCount ? words - c.wordCount : uint256(c.wordCount) - words;
        return wdiff <= 2;
    }

    function _update(address from, address to, uint256 value)
        internal
        override
    {
        // Allow minting (from == address(0))
        // Allow LPVault transfers for LP creation
        // Block all other transfers before LP deployed
        if (!lpDeployed && from != address(0)) {
            require(from == lpVault, "Transfers locked until LP deployed");
        }
        super._update(from, to, value);
    }
}
