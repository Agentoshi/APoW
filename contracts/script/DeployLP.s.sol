// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console, Script} from "forge-std/Script.sol";

import {LPVault} from "../src/LPVault.sol";

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

/// @title DeployLP — Deploy liquidity pool for AgentCoin/USDC
/// @notice Swaps vault ETH → USDC via Uniswap, then calls lpVault.deployLP()
///         to create and lock a full-range AGENT/USDC LP position.
contract DeployLP is Script {
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant QUOTER_V2 = 0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address lpVaultAddr = vm.envAddress("LP_VAULT_ADDRESS");
        LPVault lpVault = LPVault(payable(lpVaultAddr));

        console.log("=== DeployLP Pre-flight ===");
        console.log("Deployer:", deployer);
        console.log("LPVault:", lpVaultAddr);

        // Pre-flight checks
        require(block.chainid == 8453, "Not Base mainnet");
        require(lpVault.owner() == deployer, "Not vault owner");
        require(address(lpVault.agentCoin()) != address(0), "AgentCoin not set on vault");
        require(!lpVault.lpDeployed(), "LP already deployed");
        require(
            lpVaultAddr.balance >= lpVault.LP_DEPLOY_THRESHOLD() + lpVault.UNCX_FLAT_FEE(),
            "Vault ETH below threshold"
        );

        // Compute swap amount: vault balance minus UNCX flat fee reserve
        uint256 wethAmount = lpVaultAddr.balance - lpVault.UNCX_FLAT_FEE();

        // Quote WETH → USDC via QuoterV2
        IQuoterV2.QuoteExactInputSingleParams memory quoteParams = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            amountIn: wethAmount,
            fee: 3000,
            sqrtPriceLimitX96: 0
        });

        (uint256 quotedAmount,,,) = IQuoterV2(QUOTER_V2).quoteExactInputSingle(quoteParams);

        // 3% slippage tolerance
        uint256 minUsdcOut = quotedAmount * 97 / 100;

        console.log("Vault balance (wei):", lpVaultAddr.balance);
        console.log("WETH to swap (wei):", wethAmount);
        console.log("Quoted USDC out:", quotedAmount);
        console.log("Min USDC out (3% slippage):", minUsdcOut);

        vm.startBroadcast(pk);
        lpVault.deployLP(minUsdcOut);
        vm.stopBroadcast();

        // Post-deployment checks
        require(lpVault.lpDeployed(), "lpDeployed not set");
        require(lpVault.positionTokenId() > 0, "positionTokenId not set");

        console.log("=== LP DEPLOYED ===");
        console.log("Position Token ID:", lpVault.positionTokenId());
        console.log("LP deployed:", lpVault.lpDeployed());
    }
}
