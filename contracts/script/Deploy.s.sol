// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console, Script} from "forge-std/Script.sol";

import {AgentCoin} from "../src/AgentCoin.sol";
import {LPVault} from "../src/LPVault.sol";
import {MiningAgent} from "../src/MiningAgent.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        LPVault lpVault = new LPVault(deployer);
        console.log("LPVault deployed:", address(lpVault));

        MiningAgent miningAgent = new MiningAgent();
        console.log("MiningAgent deployed:", address(miningAgent));

        AgentCoin agentCoin = new AgentCoin(address(miningAgent), address(lpVault));
        console.log("AgentCoin deployed:", address(agentCoin));

        miningAgent.setLPVault(payable(address(lpVault)));
        miningAgent.setAgentCoin(address(agentCoin));
        lpVault.setAgentCoin(address(agentCoin));

        console.log("Deployment complete");
        console.log("Deployer:", deployer);
        console.log("LPVault:", address(lpVault));
        console.log("MiningAgent:", address(miningAgent));
        console.log("AgentCoin:", address(agentCoin));

        vm.stopBroadcast();
    }
}
