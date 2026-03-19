// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";
import {Test} from "forge-std/Test.sol";

import {MiningAgent} from "../src/MiningAgent.sol";
import {IAgentCoin} from "../src/interfaces/IAgentCoin.sol";

contract MockAgentCoin is IAgentCoin {
    mapping(uint256 => uint256) public mineCounts;
    mapping(uint256 => uint256) public earnings;

    function setStats(uint256 tokenId, uint256 mineCount, uint256 earned) external {
        mineCounts[tokenId] = mineCount;
        earnings[tokenId] = earned;
    }

    function tokenMineCount(uint256 tokenId) external view returns (uint256) {
        return mineCounts[tokenId];
    }

    function tokenEarnings(uint256 tokenId) external view returns (uint256) {
        return earnings[tokenId];
    }

    function setLPDeployed() external {
        // Mock implementation - do nothing
    }
}

contract MiningAgentTest is Test {
    using stdStorage for StdStorage;

    MiningAgent internal miningAgent;
    MockAgentCoin internal mockAgentCoin;

    address internal user = makeAddr("user");
    address payable internal lpVault = payable(makeAddr("lpVault"));

    function setUp() public {
        miningAgent = new MiningAgent();
        mockAgentCoin = new MockAgentCoin();

        miningAgent.setLPVault(lpVault);
        miningAgent.setAgentCoin(address(mockAgentCoin));

        vm.deal(user, 10 ether);
    }

    function testGetChallenge() public {
        vm.prevrandao(uint256(11));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory challenge = miningAgent.getChallenge(user);

        bytes32 seed = miningAgent.challengeSeeds(user);
        assertTrue(seed != bytes32(0));
        assertEq(miningAgent.challengeTimestamps(user), block.timestamp);

        MiningAgent.SMHLChallenge memory expected = _deriveChallenge(seed);
        assertEq(challenge.targetAsciiSum, expected.targetAsciiSum);
        assertEq(challenge.firstNChars, expected.firstNChars);
        assertEq(challenge.wordCount, expected.wordCount);
        assertEq(challenge.charPosition, expected.charPosition);
        assertEq(challenge.charValue, expected.charValue);
        assertEq(challenge.totalLength, expected.totalLength);

        assertGe(challenge.firstNChars, 5);
        assertLe(challenge.firstNChars, 10);
        assertGe(challenge.wordCount, 3);
        assertLe(challenge.wordCount, 7);
        assertGe(challenge.totalLength, 20);
        assertLe(challenge.totalLength, 50);
        assertGe(challenge.charValue, 97);
        assertLe(challenge.charValue, 122);
        assertLt(challenge.charPosition, challenge.totalLength);
    }

    function testMintWithValidSMHL() public {
        uint256 randomness = 123456;
        vm.prevrandao(randomness);

        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory challenge = miningAgent.getChallenge(user);

        string memory solution = _solveChallenge(challenge);
        uint256 mintPrice = miningAgent.getMintPrice();
        uint256 expectedMintBlock = block.number;
        (uint8 expectedRarity, uint16 expectedHashpower) =
            _determineRarity(keccak256(abi.encodePacked(bytes32(randomness), user, uint256(1))));

        vm.prank(user, user);
        miningAgent.mint{value: mintPrice}(solution);

        assertEq(miningAgent.ownerOf(1), user);
        assertEq(miningAgent.rarity(1), expectedRarity);
        assertEq(miningAgent.hashpower(1), expectedHashpower);
        assertEq(miningAgent.mintBlock(1), expectedMintBlock);
        assertEq(miningAgent.challengeSeeds(user), bytes32(0));
        assertEq(miningAgent.challengeTimestamps(user), 0);
    }

    function testMintExpiredChallenge() public {
        vm.prevrandao(uint256(22));

        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory challenge = miningAgent.getChallenge(user);
        string memory solution = _solveChallenge(challenge);
        uint256 price = miningAgent.getMintPrice();

        // Warp past the challenge window
        vm.warp(block.timestamp + 21);

        vm.prank(user, user);
        vm.expectRevert("Expired");
        miningAgent.mint{value: price}(solution);
    }

    function testMintPricing() public {
        // First mint: MAX_PRICE = 0.002 ETH
        assertEq(miningAgent.getMintPrice(), 0.002 ether);

        uint256 slot = stdstore.target(address(miningAgent)).sig("nextTokenId()").find();

        // After 100 mints: 95% of MAX = 0.0019 ETH
        vm.store(address(miningAgent), bytes32(slot), bytes32(uint256(101)));
        assertEq(miningAgent.getMintPrice(), 0.0019 ether);

        // After 1000 mints (10 steps): 0.002 * 0.95^10 ≈ 0.001197 ETH
        vm.store(address(miningAgent), bytes32(slot), bytes32(uint256(1_001)));
        uint256 price1k = miningAgent.getMintPrice();
        assertTrue(price1k > 0.001190 ether && price1k < 0.001200 ether, "1k price out of range");

        // Each step drops by 5% — verify step N+1 = step N * 95/100
        vm.store(address(miningAgent), bytes32(slot), bytes32(uint256(501)));
        uint256 price500 = miningAgent.getMintPrice();
        vm.store(address(miningAgent), bytes32(slot), bytes32(uint256(601)));
        uint256 price600 = miningAgent.getMintPrice();
        assertEq(price600, (price500 * 95) / 100);

        // At 10k+ (sold out): MIN_PRICE floor
        vm.store(address(miningAgent), bytes32(slot), bytes32(uint256(10_001)));
        assertEq(miningAgent.getMintPrice(), 0.0002 ether);
    }

    function testMintFeeForwarding() public {
        vm.prevrandao(uint256(33));

        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory challenge = miningAgent.getChallenge(user);
        string memory solution = _solveChallenge(challenge);
        uint256 mintPrice = miningAgent.getMintPrice();
        uint256 vaultBalanceBefore = lpVault.balance;

        vm.prank(user, user);
        miningAgent.mint{value: mintPrice}(solution);

        assertEq(lpVault.balance, vaultBalanceBefore + mintPrice);
        assertEq(address(miningAgent).balance, 0);
    }

    function testSupplyCap() public {
        uint256 slot = stdstore.target(address(miningAgent)).sig("nextTokenId()").find();
        vm.store(address(miningAgent), bytes32(slot), bytes32(uint256(10_001)));
        assertEq(miningAgent.nextTokenId(), 10_001);

        vm.prevrandao(uint256(44));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory challenge = miningAgent.getChallenge(user);
        string memory solution = _solveChallenge(challenge);
        uint256 price = miningAgent.getMintPrice();

        vm.prank(user, user);
        vm.expectRevert("Sold out");
        miningAgent.mint{value: price}(solution);
    }

    function testTokenURI() public {
        vm.prevrandao(uint256(55));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory challenge = miningAgent.getChallenge(user);
        string memory solution = _solveChallenge(challenge);
        uint256 price = miningAgent.getMintPrice();

        vm.prank(user, user);
        miningAgent.mint{value: price}(solution);

        mockAgentCoin.setStats(1, 12, 34 ether);
        string memory uri = miningAgent.tokenURI(1);

        assertTrue(_startsWith(uri, "data:application/json;base64,"));
    }

    function _deriveChallenge(bytes32 seed) internal pure returns (MiningAgent.SMHLChallenge memory challenge) {
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

    function _determineRarity(bytes32 seed) internal pure returns (uint8 rarityTier, uint16 hp) {
        uint256 roll = uint256(seed) % 100;
        if (roll < 1) return (4, 500);
        if (roll < 5) return (3, 300);
        if (roll < 15) return (2, 200);
        if (roll < 40) return (1, 150);
        return (0, 100);
    }

    function _solveChallenge(MiningAgent.SMHLChallenge memory challenge) internal pure returns (string memory) {
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

            uint256 add = remaining > 93 ? 93 : remaining;
            solution[i] = bytes1(uint8(solution[i]) + uint8(add));
            remaining -= add;
        }

        require(remaining == 0, "Unsolvable challenge");

        if (challenge.charPosition >= challenge.firstNChars) {
            solution[challenge.charPosition] = bytes1(challenge.charValue);
        }

        return string(solution);
    }

    function _startsWith(string memory value, string memory prefix) internal pure returns (bool) {
        bytes memory valueBytes = bytes(value);
        bytes memory prefixBytes = bytes(prefix);
        if (prefixBytes.length > valueBytes.length) {
            return false;
        }

        for (uint256 i = 0; i < prefixBytes.length; ++i) {
            if (valueBytes[i] != prefixBytes[i]) {
                return false;
            }
        }

        return true;
    }
}
