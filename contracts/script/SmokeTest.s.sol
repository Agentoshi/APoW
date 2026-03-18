// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console, Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {FakeToken} from "../src/smoke/FakeToken.sol";
import {FakeVault} from "../src/smoke/FakeVault.sol";
import {FakeNFT} from "../src/smoke/FakeNFT.sol";

/// @title SmokeTest1 — ERC20 deploy + transfer lock verification
/// @notice ~0.001 ETH gas. Proves contract deployment + _update() lock on real Base.
contract SmokeTest1 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address testRecipient = address(0xdead);

        console.log("=== Smoke Test 1: ERC20 Transfer Lock ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        require(block.chainid == 8453, "Not Base mainnet");

        vm.startBroadcast(pk);

        // Deploy FakeToken
        FakeToken token = new FakeToken();
        console.log("FakeToken deployed:", address(token));

        // Verify initial state
        require(token.balanceOf(deployer) == 1_000_000e18, "Bad mint");
        require(!token.transfersUnlocked(), "Should be locked");

        // Deployer CAN transfer while locked (like LPVault in real system)
        token.transfer(testRecipient, 100e18);
        require(token.balanceOf(testRecipient) == 100e18, "Deployer transfer failed");

        // Unlock transfers
        token.unlock();
        require(token.transfersUnlocked(), "Should be unlocked");

        vm.stopBroadcast();

        console.log("PASS: ERC20 deploy + transfer lock works on Base mainnet");
    }
}

/// @title SmokeTest2 — Uniswap V3 pool creation
/// @notice ~0.004 ETH (gas + tiny liquidity). Proves real Uniswap interaction.
///         Does NOT lock via UNCX. Liquidity can be withdrawn after test.
contract SmokeTest2 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("=== Smoke Test 2: Uniswap V3 Pool Creation ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        require(block.chainid == 8453, "Not Base mainnet");

        vm.startBroadcast(pk);

        // Deploy FakeToken (unlocked for LP)
        FakeToken token = new FakeToken();
        token.unlock();
        console.log("FakeToken deployed:", address(token));

        // Deploy FakeVault
        FakeVault vault = new FakeVault(address(token));
        console.log("FakeVault deployed:", address(vault));

        // Send ETH to vault for LP (~0.001 ETH for tiny pool)
        (bool sent,) = address(vault).call{value: 0.001 ether}("");
        require(sent, "ETH send failed");

        // Send FakeToken to vault
        token.transfer(address(vault), 100_000e18);

        // Deploy LP (minUsdcOut = 0 for smoke test — don't care about slippage)
        vault.deployLP(0);

        // Verify position exists
        require(vault.positionTokenId() > 0, "No position minted");
        require(vault.positionLiquidity() > 0, "No liquidity");
        console.log("Position ID:", vault.positionTokenId());
        console.log("Liquidity:", uint256(vault.positionLiquidity()));

        // Withdraw liquidity to recover tokens
        vault.withdrawLP();
        require(vault.positionLiquidity() == 0, "Liquidity not withdrawn");

        vm.stopBroadcast();

        console.log("PASS: Uniswap V3 pool creation + position mint works on Base mainnet");
    }
}

/// @title SmokeTest3 — SMHL challenge + NFT mint
/// @notice ~0.001 ETH gas. Proves SMHL on-chain verification with real block timing.
///         NOTE: This test requires solving an SMHL challenge between getChallenge()
///         and mint() within 20 seconds. Run the helper script to solve + submit.
contract SmokeTest3 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("=== Smoke Test 3: SMHL Challenge + NFT Mint ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        require(block.chainid == 8453, "Not Base mainnet");

        vm.startBroadcast(pk);

        // Deploy FakeNFT
        FakeNFT nft = new FakeNFT();
        console.log("FakeNFT deployed:", address(nft));

        // Request challenge (this tx gets mined, sets block.prevrandao)
        FakeNFT.SMHLChallenge memory challenge = nft.getChallenge(deployer);
        console.log("Challenge issued:");
        console.log("  targetAsciiSum:", challenge.targetAsciiSum);
        console.log("  firstNChars:", challenge.firstNChars);
        console.log("  wordCount:", challenge.wordCount);
        console.log("  charPosition:", challenge.charPosition);
        console.log("  charValue:", challenge.charValue);
        console.log("  totalLength:", challenge.totalLength);

        vm.stopBroadcast();

        // NOTE: At this point, a separate script/bot must:
        // 1. Read the challenge parameters from the logs above
        // 2. Solve the SMHL challenge (construct valid string)
        // 3. Call nft.mint(solution) within 20 seconds
        //
        // For the smoke test, we'll use a companion TypeScript script
        // that reads the challenge, calls the LLM to solve, and submits.
        //
        // Alternatively, run SmokeTest3Solve with the solution string.

        console.log("FakeNFT address for solve step:", address(nft));
        console.log("ACTION REQUIRED: Solve SMHL challenge and call mint() within 20s");
    }
}
