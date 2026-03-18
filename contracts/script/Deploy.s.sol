// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console, Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AgentCoin} from "../src/AgentCoin.sol";
import {LPVault} from "../src/LPVault.sol";
import {MiningAgent} from "../src/MiningAgent.sol";

contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        require(block.chainid == 8453, "Not Base mainnet");

        vm.startBroadcast(pk);

        LPVault lpVault = new LPVault(deployer);
        MiningAgent miningAgent = new MiningAgent();
        AgentCoin agentCoin = new AgentCoin(address(miningAgent), address(lpVault));

        miningAgent.setLPVault(payable(address(lpVault)));
        miningAgent.setAgentCoin(address(agentCoin));
        lpVault.setAgentCoin(address(agentCoin));

        vm.stopBroadcast();

        // Post-deployment verification (read-only)
        require(!agentCoin.lpDeployed(), "lpDeployed should be false");
        require(!lpVault.lpDeployed(), "vault lpDeployed should be false");
        require(
            IERC20(address(agentCoin)).balanceOf(address(lpVault)) == 2_100_000e18,
            "LP reserve wrong"
        );
        require(lpVault.owner() == deployer, "Vault owner wrong");
        require(miningAgent.owner() == deployer, "MA owner wrong");
        require(address(miningAgent.lpVault()) == address(lpVault), "MA lpVault wrong");
        require(miningAgent.agentCoin() == address(agentCoin), "MA agentCoin wrong");
        require(address(lpVault.agentCoin()) == address(agentCoin), "Vault agentCoin wrong");

        console.log("=== DEPLOYED ===");
        console.log("AgentCoin:", address(agentCoin));
        console.log("MiningAgent:", address(miningAgent));
        console.log("LPVault:", address(lpVault));
        console.log("lpDeployed:", agentCoin.lpDeployed());
        console.log("LP Reserve:", IERC20(address(agentCoin)).balanceOf(address(lpVault)));
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Verify system: mint an NFT, mine a token, check transfer lock");
        console.log("2. Renounce ownership on all contracts:");
        console.log("   forge script script/Renounce.s.sol --rpc-url $BASE_RPC --broadcast");
        console.log("3. Update miner client addresses in .env:");
        console.log("   MINING_AGENT_ADDRESS=", address(miningAgent));
        console.log("   AGENT_COIN_ADDRESS=", address(agentCoin));
    }
}
