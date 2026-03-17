// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console, Script} from "forge-std/Script.sol";
import {MiningAgent} from "../src/MiningAgent.sol";

contract TestnetMint is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address miningAgentAddr = vm.envAddress("MINING_AGENT");

        MiningAgent ma = MiningAgent(miningAgentAddr);

        console.log("Deployer:", deployer);
        console.log("MiningAgent:", miningAgentAddr);
        console.log("Mint price:", ma.getMintPrice());
        console.log("Next token ID:", ma.nextTokenId());

        uint256 mintPrice = ma.getMintPrice();

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: getChallenge
        MiningAgent.SMHLChallenge memory challenge = ma.getChallenge(deployer);

        console.log("Challenge received:");
        console.log("  targetAsciiSum:", challenge.targetAsciiSum);
        console.log("  firstNChars:", challenge.firstNChars);
        console.log("  wordCount:", challenge.wordCount);
        console.log("  charPosition:", challenge.charPosition);
        console.log("  charValue:", challenge.charValue);
        console.log("  totalLength:", challenge.totalLength);

        // Step 2: Solve SMHL (deterministic solver from test)
        string memory solution = _solveChallenge(challenge);
        console.log("Solution:", solution);
        console.log("Solution length:", bytes(solution).length);

        // Step 3: Mint
        ma.mint{value: mintPrice}(solution);

        uint256 tokenId = ma.nextTokenId() - 1;
        console.log("Minted token ID:", tokenId);
        console.log("Owner:", ma.ownerOf(tokenId));
        console.log("Rarity:", ma.rarity(tokenId));
        console.log("Hashpower:", ma.hashpower(tokenId));
        console.log("Mint block:", ma.mintBlock(tokenId));

        vm.stopBroadcast();

        // Read tokenURI (view call, no broadcast needed)
        string memory uri = ma.tokenURI(tokenId);
        console.log("TokenURI length:", bytes(uri).length);
        console.log("TokenURI starts with data:application/json:", _startsWith(uri, "data:application/json;base64,"));
    }

    function _solveChallenge(MiningAgent.SMHLChallenge memory challenge) internal pure returns (string memory) {
        bytes memory solution = new bytes(challenge.totalLength);
        bool[] memory isSpace = new bool[](challenge.totalLength);

        // Fill with 'A' (ASCII 65)
        for (uint256 i = 0; i < challenge.totalLength; ++i) {
            solution[i] = bytes1(uint8(65));
        }

        // Place spaces for word separators (wordCount - 1 spaces)
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

        // Set char constraint and compute ASCII sum for first N chars
        uint256 currentSum;
        for (uint256 i = 0; i < challenge.firstNChars; ++i) {
            if (i == challenge.charPosition) {
                solution[i] = bytes1(challenge.charValue);
            } else {
                solution[i] = bytes1(uint8(33)); // '!'
            }
            currentSum += uint8(solution[i]);
        }

        // Adjust ASCII sum to match target
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

        // Place charValue at charPosition if it's outside firstNChars
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
