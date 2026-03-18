// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console, Script} from "forge-std/Script.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AgentCoin} from "../src/AgentCoin.sol";
import {LPVault} from "../src/LPVault.sol";
import {MiningAgent} from "../src/MiningAgent.sol";

/// @title Renounce — Renounce ownership on all contracts post-deploy
/// @notice Run AFTER verifying the system works (mint, mine, transfer lock).
///         This makes the protocol fully immutable — no admin functions remain.
///         IRREVERSIBLE. Double-check all pointers before running.
contract Renounce is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address miningAgentAddr = vm.envAddress("MINING_AGENT_ADDRESS");
        address agentCoinAddr = vm.envAddress("AGENT_COIN_ADDRESS");
        address lpVaultAddr = vm.envAddress("LP_VAULT_ADDRESS");

        MiningAgent miningAgent = MiningAgent(miningAgentAddr);
        AgentCoin agentCoin = AgentCoin(agentCoinAddr);
        LPVault lpVault = LPVault(payable(lpVaultAddr));

        console.log("=== Pre-Renounce Verification ===");
        console.log("Deployer:", deployer);
        require(block.chainid == 8453, "Not Base mainnet");

        // Verify all pointers are set correctly before making immutable
        require(address(miningAgent.lpVault()) == lpVaultAddr, "MA.lpVault wrong");
        require(miningAgent.agentCoin() == agentCoinAddr, "MA.agentCoin wrong");
        require(address(lpVault.agentCoin()) == agentCoinAddr, "Vault.agentCoin wrong");
        require(address(agentCoin.miningAgent()) == miningAgentAddr, "AC.miningAgent wrong");
        require(agentCoin.lpVault() == lpVaultAddr, "AC.lpVault wrong");

        // Verify current ownership
        require(miningAgent.owner() == deployer, "Not MA owner");
        require(agentCoin.owner() == deployer, "Not AC owner");
        require(lpVault.owner() == deployer, "Not Vault owner");

        console.log("All pointers verified. Renouncing ownership...");

        vm.startBroadcast(pk);
        miningAgent.renounceOwnership();
        agentCoin.renounceOwnership();
        lpVault.renounceOwnership();
        vm.stopBroadcast();

        // Verify renunciation
        require(miningAgent.owner() == address(0), "MA ownership not renounced");
        require(agentCoin.owner() == address(0), "AC ownership not renounced");
        require(lpVault.owner() == address(0), "Vault ownership not renounced");

        console.log("=== OWNERSHIP RENOUNCED ===");
        console.log("MiningAgent owner:", miningAgent.owner());
        console.log("AgentCoin owner:", agentCoin.owner());
        console.log("LPVault owner:", lpVault.owner());
        console.log("Protocol is now fully immutable.");
    }
}
