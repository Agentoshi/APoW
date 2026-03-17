// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {IAgentCoin} from "./interfaces/IAgentCoin.sol";
import {IMiningAgent} from "./interfaces/IMiningAgent.sol";
import {MinerArt} from "./lib/MinerArt.sol";

contract MiningAgent is ERC721Enumerable, Ownable, ReentrancyGuardTransient, IMiningAgent {
    uint256 public constant MAX_SUPPLY = 100_000;
    uint256 public constant MAX_PRICE = 0.00217 ether; // ~$5.00 at $2,300/ETH
    uint256 public constant MIN_PRICE = 0.00005 ether; // ~$0.12 floor
    uint256 public constant STEP_SIZE = 1_000; // price updates every 1k mints
    uint256 public constant DECAY_NUM = 90; // 10% decay per step (90/100)
    uint256 public constant DECAY_DEN = 100;
    uint256 public constant CHALLENGE_DURATION = 20;

    struct SMHLChallenge {
        uint16 targetAsciiSum;
        uint8 firstNChars;
        uint8 wordCount;
        uint8 charPosition;
        uint8 charValue;
        uint16 totalLength;
    }

    event MinerMinted(address indexed owner, uint256 indexed tokenId, uint8 rarity, uint16 hashpower);
    event AgentCoinSet(address agentCoin);
    event LPVaultSet(address lpVault);

    address payable public lpVault;
    address public agentCoin;
    uint256 public challengeNonce;
    uint256 public nextTokenId = 1;

    mapping(uint256 => uint16) public hashpower;
    mapping(uint256 => uint8) public rarity;
    mapping(uint256 => uint256) public mintBlock;

    mapping(address => bytes32) public challengeSeeds;
    mapping(address => uint256) public challengeTimestamps;

    constructor() ERC721("AgentCoin Miner", "MINER") Ownable(msg.sender) {}

    function getChallenge(address minter) external returns (SMHLChallenge memory) {
        bytes32 seed = keccak256(abi.encodePacked(minter, block.prevrandao, challengeNonce++));
        challengeSeeds[minter] = seed;
        challengeTimestamps[minter] = block.timestamp;
        return _deriveChallenge(seed);
    }

    function mint(string calldata solution) external payable nonReentrant {
        require(msg.sender == tx.origin, "No contracts");
        require(nextTokenId <= MAX_SUPPLY, "Sold out");
        require(challengeTimestamps[msg.sender] > 0, "No challenge");
        require(block.timestamp <= challengeTimestamps[msg.sender] + CHALLENGE_DURATION, "Expired");
        require(lpVault != address(0), "LPVault not set");
        require(msg.value >= getMintPrice(), "Insufficient fee");

        SMHLChallenge memory challenge = _deriveChallenge(challengeSeeds[msg.sender]);
        require(_verifySMHL(solution, challenge), "Invalid SMHL");

        delete challengeSeeds[msg.sender];
        delete challengeTimestamps[msg.sender];

        uint256 tokenId = nextTokenId;
        nextTokenId = tokenId + 1;

        (uint8 rarityTier, uint16 hp) =
            _determineRarity(keccak256(abi.encodePacked(block.prevrandao, msg.sender, tokenId)));

        rarity[tokenId] = rarityTier;
        hashpower[tokenId] = hp;
        mintBlock[tokenId] = block.number;

        _mint(msg.sender, tokenId);

        emit MinerMinted(msg.sender, tokenId, rarityTier, hp);

        (bool success,) = lpVault.call{value: msg.value}("");
        require(success, "Fee forward failed");
    }

    function getMintPrice() public view returns (uint256) {
        uint256 minted = nextTokenId - 1;
        if (minted >= MAX_SUPPLY) return MIN_PRICE;
        // Exponential decay: price = MAX_PRICE * (90/100)^steps, floored at MIN_PRICE
        // 10% drop every 1,000 mints — large steps early, small steps late (~$56k total)
        uint256 steps = minted / STEP_SIZE;
        uint256 price = MAX_PRICE;
        for (uint256 i = 0; i < steps; ++i) {
            price = (price * DECAY_NUM) / DECAY_DEN;
        }
        return price < MIN_PRICE ? MIN_PRICE : price;
    }

    function setAgentCoin(address _agentCoin) external onlyOwner {
        require(_agentCoin != address(0), "Invalid AgentCoin");
        require(agentCoin == address(0), "Already set");
        agentCoin = _agentCoin;
        emit AgentCoinSet(_agentCoin);
    }

    function setLPVault(address payable _lpVault) external onlyOwner {
        require(_lpVault != address(0), "Invalid LPVault");
        require(lpVault == address(0), "Already set");
        lpVault = _lpVault;
        emit LPVaultSet(_lpVault);
    }

    function _deriveChallenge(bytes32 seed) internal pure returns (SMHLChallenge memory challenge) {
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

    function _verifySMHL(string calldata solution, SMHLChallenge memory c) internal pure returns (bool) {
        bytes calldata chars = bytes(solution);
        if (chars.length != c.totalLength) {
            return false;
        }

        if (uint8(chars[c.charPosition]) != c.charValue) {
            return false;
        }

        uint256 asciiSum;
        for (uint256 i = 0; i < c.firstNChars; ++i) {
            asciiSum += uint8(chars[i]);
        }
        if (asciiSum != c.targetAsciiSum) {
            return false;
        }

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

    // Required overrides for ERC721Enumerable + IMiningAgent
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Enumerable, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        _requireOwned(tokenId);

        uint256 mineCount;
        uint256 earnings;
        if (agentCoin != address(0)) {
            mineCount = IAgentCoin(agentCoin).tokenMineCount(tokenId);
            earnings = IAgentCoin(agentCoin).tokenEarnings(tokenId);
        }

        return MinerArt.tokenURI(tokenId, rarity[tokenId], hashpower[tokenId], mintBlock[tokenId], mineCount, earnings);
    }

    function _determineRarity(bytes32 seed) internal pure returns (uint8 rarityTier, uint16 hp) {
        uint256 roll = uint256(seed) % 100;
        if (roll < 1) return (4, 500);
        if (roll < 5) return (3, 300);
        if (roll < 15) return (2, 200);
        if (roll < 40) return (1, 150);
        return (0, 100);
    }
}
