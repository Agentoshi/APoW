// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AgentCoin} from "../src/AgentCoin.sol";
import {MiningAgent} from "../src/MiningAgent.sol";
import {LPVault, IWETH, IUniswapV3Factory} from "../src/LPVault.sol";

/// @notice Fork tests against real Base mainnet state.
/// Run with: forge test --match-path test/LPVaultFork.t.sol --fork-url $BASE_RPC -vvv
contract LPVaultForkTest is Test {
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address internal constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address internal constant UNCX_V3_LOCKER = 0x231278eDd38B00B07fBd52120CEf685B9BaEBCC1;

    MiningAgent internal ma;
    AgentCoin internal ac;
    LPVault internal lpVault;

    address internal deployer = makeAddr("deployer");

    modifier onlyFork() {
        // Skip if not running on a fork
        try vm.activeFork() returns (uint256) {
            _;
        } catch {
            return;
        }
    }

    function setUp() public onlyFork {
        vm.startPrank(deployer);

        ma = new MiningAgent();
        lpVault = new LPVault(deployer);
        ac = new AgentCoin(address(ma), address(lpVault));

        ma.setLPVault(payable(address(lpVault)));
        ma.setAgentCoin(address(ac));
        lpVault.setAgentCoin(address(ac));

        vm.stopPrank();
    }

    function testFork_DeployLP_RealUniswapV3() public onlyFork {
        // Fund vault with enough ETH
        vm.deal(address(lpVault), 5 ether);

        // Verify LP reserve is in vault
        assertEq(ac.balanceOf(address(lpVault)), 2_100_000e18);

        // Deploy LP with 0 slippage for fork test (Uniswap pool is fresh)
        vm.prank(deployer);
        lpVault.deployLP(0);

        // Verify LP deployed
        assertTrue(lpVault.lpDeployed());
        assertTrue(lpVault.positionTokenId() > 0);

        // Verify no stranded ETH
        assertEq(address(lpVault).balance, 0);

        // Verify no stranded WETH
        assertEq(IERC20(WETH).balanceOf(address(lpVault)), 0);

        // Verify AGENT tokens consumed (UNCX lock returns negligible dust)
        assertTrue(ac.balanceOf(address(lpVault)) < 1e16, "Too much AGENT dust remaining");

        // Log position info
        console.log("Position token ID:", lpVault.positionTokenId());
        console.log("USDC in router:", IERC20(USDC).balanceOf(SWAP_ROUTER));
    }

    function testFork_DeployLP_UNCXLockParams() public onlyFork {
        vm.deal(address(lpVault), 5 ether);

        vm.prank(deployer);
        lpVault.deployLP(0);

        // UNCX lock succeeded (fee forwarded internally by UNCX)
        assertTrue(lpVault.lpDeployed());
        assertTrue(lpVault.positionTokenId() > 0);
    }

    function testFork_DeployLP_WithSlippageProtection() public onlyFork {
        vm.deal(address(lpVault), 5 ether);

        // Try with unreasonably high minUsdcOut — should revert
        vm.prank(deployer);
        vm.expectRevert(); // Uniswap will revert with "Too little received"
        lpVault.deployLP(type(uint256).max);
    }

    function testFork_FullLifecycle_MintAndDeploy() public onlyFork {
        // 1. Mint some NFTs to generate fees
        vm.deal(address(lpVault), 5 ether);

        // 2. Deploy LP
        vm.prank(deployer);
        lpVault.deployLP(0);
        assertTrue(lpVault.lpDeployed());

        // 3. Mine some AGENT
        vm.store(address(ac), bytes32(uint256(8)), bytes32(type(uint256).max)); // easy target
        vm.roll(block.number + 1);

        // Mint an NFT for mining
        address miner = makeAddr("miner");
        uint256 price = ma.getMintPrice();
        vm.deal(miner, price);

        vm.prank(miner, miner);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(miner);
        string memory sol = _solveMiningAgentChallenge(c);

        vm.prank(miner, miner);
        ma.mint{value: price}(sol);

        uint256 tokenId = ma.nextTokenId() - 1;

        // Mine
        vm.roll(block.number + 1);
        (, , AgentCoin.SMHLChallenge memory mc) = ac.getMiningChallenge();
        string memory msol = _solveAgentCoinChallenge(mc);

        vm.prank(miner, miner);
        ac.mine(0, msol, tokenId);

        assertTrue(ac.balanceOf(miner) > 0);
        console.log("Miner earned:", ac.balanceOf(miner));
    }

    function testFork_FactoryAddressMatchesPositionManager() public onlyFork {
        vm.deal(address(lpVault), 5 ether);

        vm.prank(deployer);
        lpVault.deployLP(0);

        // Verify our factory constant matches what PositionManager uses
        address pool = IUniswapV3Factory(0x33128a8fC17869897dcE68Ed026d694621f6FDfD).getPool(
            address(ac), USDC, 3000
        );
        assertTrue(pool != address(0), "Pool should exist after deployment");
    }

    function testFork_TransferLockFullCycle() public onlyFork {
        // 1. Set easy mining target
        vm.store(address(ac), bytes32(uint256(8)), bytes32(type(uint256).max));
        vm.roll(block.number + 1);

        // 2. Mint an NFT
        address miner = makeAddr("miner");
        uint256 price = ma.getMintPrice();
        vm.deal(miner, price + 1 ether);

        vm.prank(miner, miner);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(miner);
        string memory sol = _solveMiningAgentChallenge(c);
        vm.prank(miner, miner);
        ma.mint{value: price}(sol);
        uint256 tokenId = ma.nextTokenId() - 1;

        // 3. Mine AGENT tokens
        vm.roll(block.number + 1);
        (, , AgentCoin.SMHLChallenge memory mc) = ac.getMiningChallenge();
        string memory msol = _solveAgentCoinChallenge(mc);
        vm.prank(miner, miner);
        ac.mine(0, msol, tokenId);
        assertTrue(ac.balanceOf(miner) > 0);

        // 4. Try transfer — should FAIL (locked)
        vm.prank(miner);
        vm.expectRevert("Transfers locked until LP deployed");
        ac.transfer(deployer, 1);

        // 5. Deploy LP
        vm.deal(address(lpVault), 5 ether);
        vm.prank(deployer);
        lpVault.deployLP(0);

        // 6. Try transfer — should SUCCEED (unlocked)
        vm.prank(miner);
        ac.transfer(deployer, 1);
        assertEq(ac.balanceOf(deployer), 1);
    }

    function testFork_EmergencyUnwrapWeth() public onlyFork {
        vm.deal(address(lpVault), 5 ether);

        // Manually wrap ETH (simulating partial deployLP failure)
        vm.prank(address(lpVault));
        IWETH(WETH).deposit{value: 4.97 ether}();

        // Emergency unwrap
        vm.prank(deployer);
        lpVault.emergencyUnwrapWeth();

        // WETH should be zero, ETH should be back
        assertEq(IERC20(WETH).balanceOf(address(lpVault)), 0);
        assertTrue(address(lpVault).balance > 4.9 ether);
    }

    function testFork_MiningBypassImpossible() public onlyFork {
        address attacker = makeAddr("attacker");

        // Try calling setLPDeployed directly
        vm.prank(attacker);
        vm.expectRevert("Only LPVault");
        ac.setLPDeployed();

        // Try transfer from vault without approval
        vm.prank(attacker);
        vm.expectRevert();
        IERC20(address(ac)).transferFrom(address(lpVault), attacker, 1);
    }

    // ============ Helpers ============

    function _solveMiningAgentChallenge(MiningAgent.SMHLChallenge memory c) internal pure returns (string memory) {
        return _solveSMHL(c.targetAsciiSum, c.firstNChars, c.wordCount, c.charPosition, c.charValue, c.totalLength);
    }

    function _solveAgentCoinChallenge(AgentCoin.SMHLChallenge memory c) internal pure returns (string memory) {
        return _solveSMHL(c.targetAsciiSum, c.firstNChars, c.wordCount, c.charPosition, c.charValue, c.totalLength);
    }

    function _solveSMHL(
        uint16 targetAsciiSum,
        uint8 firstNChars,
        uint8 wordCount,
        uint8 charPosition,
        uint8 charValue,
        uint16 totalLength
    ) internal pure returns (string memory) {
        bytes memory solution = new bytes(totalLength);
        bool[] memory isSpace = new bool[](totalLength);

        for (uint256 i = 0; i < totalLength; ++i) {
            solution[i] = bytes1(uint8(65));
        }
        solution[charPosition] = bytes1(charValue);

        uint256 spacesNeeded = uint256(wordCount) - 1;
        uint256 spacesPlaced;

        if (totalLength > firstNChars) {
            uint256 pos = totalLength - 2;
            while (spacesPlaced < spacesNeeded && pos >= firstNChars) {
                if (pos != charPosition && !isSpace[pos]
                    && !(pos > 0 && isSpace[pos - 1])
                    && !(pos + 1 < totalLength && isSpace[pos + 1])
                ) {
                    solution[pos] = bytes1(uint8(32));
                    isSpace[pos] = true;
                    spacesPlaced++;
                }
                if (pos == firstNChars) break;
                pos--;
            }
        }

        if (spacesPlaced < spacesNeeded && firstNChars > 1) {
            uint256 pos = uint256(firstNChars) - 1;
            while (spacesPlaced < spacesNeeded && pos >= 1) {
                if (pos != charPosition && !isSpace[pos]
                    && !(pos > 0 && isSpace[pos - 1])
                    && !(pos + 1 < totalLength && isSpace[pos + 1])
                ) {
                    solution[pos] = bytes1(uint8(32));
                    isSpace[pos] = true;
                    spacesPlaced++;
                }
                if (pos == 1) break;
                pos--;
            }
        }

        require(spacesPlaced == spacesNeeded, "Cannot place spaces");

        uint256 currentSum;
        for (uint256 i = 0; i < firstNChars; ++i) {
            if (isSpace[i]) {
                currentSum += 32;
            } else if (i == charPosition) {
                currentSum += charValue;
            } else {
                solution[i] = bytes1(uint8(33));
                currentSum += 33;
            }
        }

        uint256 remaining = uint256(targetAsciiSum) - currentSum;
        for (uint256 i = 0; i < firstNChars && remaining > 0; ++i) {
            if (i == charPosition || isSpace[i]) continue;
            uint256 maxAdd = 126 - uint8(solution[i]);
            uint256 add = remaining > maxAdd ? maxAdd : remaining;
            solution[i] = bytes1(uint8(uint8(solution[i]) + uint8(add)));
            remaining -= add;
        }

        require(remaining == 0, "Unsolvable challenge");

        if (!isSpace[charPosition]) {
            solution[charPosition] = bytes1(charValue);
        }

        return string(solution);
    }
}
