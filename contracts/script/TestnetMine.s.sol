// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console, Script} from "forge-std/Script.sol";
import {AgentCoin} from "../src/AgentCoin.sol";

contract TestnetMine is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address agentCoinAddr = vm.envAddress("AGENT_COIN");
        uint256 tokenId = vm.envUint("TOKEN_ID");

        AgentCoin ac = AgentCoin(agentCoinAddr);

        console.log("Deployer:", deployer);
        console.log("AgentCoin:", agentCoinAddr);
        console.log("Token ID:", tokenId);
        console.log("Total mines:", ac.totalMines());
        console.log("Total minted:", ac.totalMinted());
        console.log("Mining target:", ac.miningTarget());
        console.log("AGENT balance:", ac.balanceOf(deployer));

        // Step 1: Get mining challenge
        (bytes32 challengeNumber, uint256 target, AgentCoin.SMHLChallenge memory smhl) = ac.getMiningChallenge();

        console.log("Challenge number:");
        console.logBytes32(challengeNumber);
        console.log("Target:", target);
        console.log("SMHL - targetAsciiSum:", smhl.targetAsciiSum);
        console.log("SMHL - firstNChars:", smhl.firstNChars);
        console.log("SMHL - wordCount:", smhl.wordCount);
        console.log("SMHL - charPosition:", smhl.charPosition);
        console.log("SMHL - charValue:", smhl.charValue);
        console.log("SMHL - totalLength:", smhl.totalLength);

        // Step 2: Solve SMHL
        string memory smhlSolution = _solveChallenge(smhl);
        console.log("SMHL solution:", smhlSolution);

        // Step 3: Grind nonce
        uint256 nonce = _grindNonce(challengeNumber, deployer, target);
        console.log("Found nonce:", nonce);

        // Step 4: Mine
        vm.startBroadcast(deployerPrivateKey);
        ac.mine(nonce, smhlSolution, tokenId);
        vm.stopBroadcast();

        console.log("Mine successful!");
        console.log("Total mines:", ac.totalMines());
        console.log("Total minted:", ac.totalMinted());
        console.log("AGENT balance:", ac.balanceOf(deployer));
        console.log("Token mine count:", ac.tokenMineCount(tokenId));
        console.log("Token earnings:", ac.tokenEarnings(tokenId));
    }

    function _grindNonce(bytes32 challengeNumber, address miner, uint256 target) internal pure returns (uint256) {
        for (uint256 nonce = 0; nonce < 10_000_000; ++nonce) {
            uint256 digest = uint256(keccak256(abi.encodePacked(challengeNumber, miner, nonce)));
            if (digest < target) {
                return nonce;
            }
        }
        revert("No nonce found in 10M attempts");
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
