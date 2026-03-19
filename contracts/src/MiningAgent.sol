// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {IAgentCoin} from "./interfaces/IAgentCoin.sol";
import {IMiningAgent} from "./interfaces/IMiningAgent.sol";
import {MinerArt} from "./lib/MinerArt.sol";

contract MiningAgent is ERC721Enumerable, Ownable, ReentrancyGuardTransient, EIP712, IMiningAgent {
    uint256 public constant MAX_SUPPLY = 10_000;
    uint256 public constant MAX_PRICE = 0.002 ether;
    uint256 public constant MIN_PRICE = 0.0002 ether;
    uint256 public constant STEP_SIZE = 100; // price updates every 100 mints
    uint256 public constant DECAY_NUM = 95; // 5% decay per step (95/100)
    uint256 public constant DECAY_DEN = 100;
    uint256 public constant CHALLENGE_DURATION = 20;


    bytes32 private constant AGENT_WALLET_SET_TYPEHASH =
        keccak256("AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)");
    uint256 private constant MAX_DEADLINE_DELAY = 5 minutes;
    bytes32 private constant RESERVED_KEY_HASH = keccak256("agentWallet");

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
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);
    event MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue);

    address payable public lpVault;
    address public agentCoin;
    uint256 public challengeNonce;
    uint256 public nextTokenId = 1;

    mapping(uint256 => uint16) public hashpower;
    mapping(uint256 => uint8) public rarity;
    mapping(uint256 => uint256) public mintBlock;

    mapping(address => bytes32) public challengeSeeds;
    mapping(address => uint256) public challengeTimestamps;

    mapping(uint256 => string) private _agentURIs;
    mapping(uint256 => mapping(string => bytes)) private _metadata;

    constructor() ERC721("AgentCoin Miner", "MINER") Ownable(msg.sender) EIP712("MiningAgent", "1") {}

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

        _metadata[tokenId]["agentWallet"] = abi.encodePacked(msg.sender);
        emit Registered(tokenId, "", msg.sender);
        emit MinerMinted(msg.sender, tokenId, rarityTier, hp);

        (bool success,) = lpVault.call{value: msg.value}("");
        require(success, "Fee forward failed");
    }

    function getMintPrice() public view returns (uint256) {
        uint256 minted = nextTokenId - 1;
        if (minted >= MAX_SUPPLY) return MIN_PRICE;
        // Exponential decay: price = MAX_PRICE * (95/100)^steps, floored at MIN_PRICE
        // 5% drop every 100 mints, floored at MIN_PRICE
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

    // ============ ERC-8004: Agent URI ============

    function agentURI(uint256 agentId) external view returns (string memory) {
        _requireOwned(agentId);
        return _agentURIs[agentId];
    }

    function setAgentURI(uint256 agentId, string calldata newURI) external {
        address owner = _requireOwned(agentId);
        require(_isAuthorized(owner, msg.sender, agentId), "Not authorized");
        _agentURIs[agentId] = newURI;
        emit URIUpdated(agentId, newURI, msg.sender);
    }

    // ============ ERC-8004: Metadata ============

    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory) {
        _requireOwned(agentId);
        return _metadata[agentId][metadataKey];
    }

    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external {
        address owner = _requireOwned(agentId);
        require(_isAuthorized(owner, msg.sender, agentId), "Not authorized");
        require(keccak256(bytes(metadataKey)) != RESERVED_KEY_HASH, "Use setAgentWallet");
        _metadata[agentId][metadataKey] = metadataValue;
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);
    }

    // ============ ERC-8004: Agent Wallet (EIP-712 verified) ============

    function getAgentWallet(uint256 agentId) external view returns (address) {
        bytes memory raw = _metadata[agentId]["agentWallet"];
        if (raw.length == 0) return address(0);
        return address(bytes20(raw));
    }

    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external {
        address owner = _requireOwned(agentId);
        require(_isAuthorized(owner, msg.sender, agentId), "Not authorized");
        require(newWallet != address(0), "Invalid wallet");
        require(deadline >= block.timestamp, "Deadline expired");
        require(deadline <= block.timestamp + MAX_DEADLINE_DELAY, "Deadline too far");

        bytes32 structHash = keccak256(abi.encode(AGENT_WALLET_SET_TYPEHASH, agentId, newWallet, owner, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);
        require(SignatureChecker.isValidSignatureNow(newWallet, digest, signature), "Invalid signature");

        _metadata[agentId]["agentWallet"] = abi.encodePacked(newWallet);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(newWallet));
    }

    function unsetAgentWallet(uint256 agentId) external {
        address owner = _requireOwned(agentId);
        require(_isAuthorized(owner, msg.sender, agentId), "Not authorized");
        delete _metadata[agentId]["agentWallet"];
        emit MetadataSet(agentId, "agentWallet", "agentWallet", "");
    }

    // ============ ERC-8004: Utility ============

    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool) {
        address owner = _requireOwned(agentId);
        return _isAuthorized(owner, spender, agentId);
    }

    // ============ Transfer: clear agentWallet ============

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Enumerable) returns (address) {
        address from = super._update(to, tokenId, auth);
        // Clear agentWallet on transfer (not on mint or burn)
        if (from != address(0) && to != address(0)) {
            delete _metadata[tokenId]["agentWallet"];
        }
        return from;
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
