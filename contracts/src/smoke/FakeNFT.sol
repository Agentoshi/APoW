// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title FakeNFT — Smoke test for SMHL challenge system on Base mainnet
/// @notice Minimal NFT with getChallenge() + mint() using identical SMHL
///         derivation and verification logic as MiningAgent. Tests real block
///         timing and prevrandao entropy on Base L2. Fake branding. Throwaway.
contract FakeNFT is ERC721 {
    uint256 public constant CHALLENGE_DURATION = 20;

    struct SMHLChallenge {
        uint16 targetAsciiSum;
        uint8 firstNChars;
        uint8 wordCount;
        uint8 charPosition;
        uint8 charValue;
        uint16 totalLength;
    }

    event ChallengIssued(address indexed minter, bytes32 seed, uint256 timestamp);
    event Minted(address indexed minter, uint256 tokenId);

    uint256 public nextTokenId = 1;
    uint256 public challengeNonce;
    mapping(address => bytes32) public challengeSeeds;
    mapping(address => uint256) public challengeTimestamps;

    constructor() ERC721("TestAlphaNFT", "TANFT") {}

    function getChallenge(address minter) external returns (SMHLChallenge memory) {
        bytes32 seed = keccak256(abi.encodePacked(minter, block.prevrandao, challengeNonce++));
        challengeSeeds[minter] = seed;
        challengeTimestamps[minter] = block.timestamp;
        emit ChallengIssued(minter, seed, block.timestamp);
        return _deriveChallenge(seed);
    }

    function mint(string calldata solution) external {
        require(challengeTimestamps[msg.sender] > 0, "No challenge");
        require(block.timestamp <= challengeTimestamps[msg.sender] + CHALLENGE_DURATION, "Expired");

        SMHLChallenge memory challenge = _deriveChallenge(challengeSeeds[msg.sender]);
        require(_verifySMHL(solution, challenge), "Invalid SMHL");

        delete challengeSeeds[msg.sender];
        delete challengeTimestamps[msg.sender];

        uint256 tokenId = nextTokenId++;
        _mint(msg.sender, tokenId);
        emit Minted(msg.sender, tokenId);
    }

    /// @notice Read-only: get current challenge params for an address
    function getCurrentChallenge(address minter) external view returns (SMHLChallenge memory) {
        require(challengeSeeds[minter] != bytes32(0), "No active challenge");
        return _deriveChallenge(challengeSeeds[minter]);
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
}
