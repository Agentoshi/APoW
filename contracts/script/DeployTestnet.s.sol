// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console, Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AgentCoin} from "../src/AgentCoin.sol";
import {LPVault} from "../src/LPVault.sol";
import {MiningAgent} from "../src/MiningAgent.sol";

contract DeployTestnet is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        require(block.chainid == 84532, "Not Base Sepolia");

        vm.startBroadcast(pk);

        LPVault lpVault = new LPVault(deployer);
        MiningAgent miningAgent = new MiningAgent();
        AgentCoin agentCoin = new AgentCoin(address(miningAgent), address(lpVault));

        miningAgent.setLPVault(payable(address(lpVault)));
        miningAgent.setAgentCoin(address(agentCoin));
        lpVault.setAgentCoin(address(agentCoin));

        vm.stopBroadcast();

        // Post-deployment verification
        require(!agentCoin.lpDeployed(), "lpDeployed should be false");
        require(
            IERC20(address(agentCoin)).balanceOf(address(lpVault)) == 2_100_000e18,
            "LP reserve wrong"
        );
        require(miningAgent.owner() == deployer, "MA owner wrong");

        console.log("=== DEPLOYED (TESTNET) ===");
        console.log("AgentCoin:", address(agentCoin));
        console.log("MiningAgent:", address(miningAgent));
        console.log("LPVault:", address(lpVault));
    }
}
