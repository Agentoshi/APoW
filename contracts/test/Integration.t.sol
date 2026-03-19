// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {AgentCoin} from "../src/AgentCoin.sol";
import {MiningAgent} from "../src/MiningAgent.sol";
import {
    INonfungiblePositionManager,
    ISwapRouter,
    IUNCXLocker,
    LPVault
} from "../src/LPVault.sol";

// ============ Mocks (only external infra: Uniswap/UNCX/WETH) ============

contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (msg.sender != from && allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        payable(msg.sender).transfer(amount);
    }
}

contract MockSwapRouter {
    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params) external payable returns (uint256) {
        MockToken(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        MockToken(params.tokenOut).mint(params.recipient, params.amountIn);
        return params.amountIn;
    }
}

contract MockPositionManager {
    uint256 public nextTokenId;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) public getApproved;
    bool public poolInitialized;

    function createAndInitializePoolIfNecessary(address, address, uint24, uint160)
        external
        payable
        returns (address)
    {
        poolInitialized = true;
        return address(uint160(uint256(keccak256(abi.encodePacked(msg.sender)))));
    }

    function mint(INonfungiblePositionManager.MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        MockToken(params.token0).transferFrom(msg.sender, address(this), params.amount0Desired);
        MockToken(params.token1).transferFrom(msg.sender, address(this), params.amount1Desired);
        tokenId = ++nextTokenId;
        ownerOf[tokenId] = params.recipient;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
        liquidity = uint128(amount0 < amount1 ? amount0 : amount1);
    }

    function approve(address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == msg.sender, "Not owner");
        getApproved[tokenId] = to;
    }
}

contract MockUNCXLocker {
    uint256 public lastLockedTokenId;
    address public lastCollectAddress;
    uint256 public lastUnlockDate;
    uint256 public lastFeeReceived;
    string public lastFeeName;

    function lock(IUNCXLocker.LockParams calldata params) external payable returns (uint256) {
        lastLockedTokenId = params.nft_id;
        lastCollectAddress = params.collectAddress;
        lastUnlockDate = params.unlockDate;
        lastFeeReceived = msg.value;
        lastFeeName = params.feeName;
        return 1;
    }
}

contract MockUniswapV3Factory {
    function getPool(address, address, uint24) external pure returns (address) {
        // Return zero address to simulate pool doesn't exist
        return address(0);
    }
}

// ============ Integration Tests ============

contract IntegrationTest is Test {
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address internal constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address internal constant UNCX_V3_LOCKER = 0x231278eDd38B00B07fBd52120CEf685B9BaEBCC1;
    address internal constant UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

    MiningAgent internal ma;
    AgentCoin internal ac;
    LPVault internal lpVault;

    address internal deployer = makeAddr("deployer");
    address internal miner1 = makeAddr("miner1");
    address internal miner2 = makeAddr("miner2");

    // AgentCoin storage slots
    bytes32 internal constant SLOT_MINING_TARGET = bytes32(uint256(8));
    bytes32 internal constant SLOT_LAST_MINE_BLOCK = bytes32(uint256(9));
    bytes32 internal constant SLOT_TOTAL_MINTED = bytes32(uint256(12));

    function setUp() public {
        // Deploy external infra mocks
        vm.etch(WETH, address(new MockToken()).code);
        vm.etch(USDC, address(new MockToken()).code);
        vm.etch(SWAP_ROUTER, address(new MockSwapRouter()).code);
        vm.etch(POSITION_MANAGER, address(new MockPositionManager()).code);
        vm.etch(UNCX_V3_LOCKER, address(new MockUNCXLocker()).code);
        vm.etch(UNISWAP_V3_FACTORY, address(new MockUniswapV3Factory()).code);

        // Deploy real contracts (interconnected)
        vm.startPrank(deployer);

        ma = new MiningAgent();
        lpVault = new LPVault(deployer);
        ac = new AgentCoin(address(ma), address(lpVault));

        ma.setLPVault(payable(address(lpVault)));
        ma.setAgentCoin(address(ac));
        lpVault.setAgentCoin(address(ac));

        vm.stopPrank();

        // Set easy mining target for tests
        vm.store(address(ac), SLOT_MINING_TARGET, bytes32(type(uint256).max));
    }

    // ============ Full Lifecycle ============

    function testFullLifecycle_MintNFT_Mine_EarnAGENT() public {
        // 1. Mint an NFT
        uint256 tokenId = _mintNFT(miner1);
        assertEq(ma.ownerOf(tokenId), miner1);
        uint16 hp = ma.hashpower(tokenId);
        assertTrue(hp > 0);

        // 2. Mine AGENT tokens
        vm.roll(100);
        _mine(miner1, tokenId);

        // 3. Verify earnings
        uint256 expectedReward = (3e18 * uint256(hp)) / 100;
        assertEq(ac.balanceOf(miner1), expectedReward);
        assertEq(ac.tokenMineCount(tokenId), 1);
        assertEq(ac.tokenEarnings(tokenId), expectedReward);
    }

    function testFullLifecycle_MintFees_FundLP() public {
        // Mint several NFTs — all fees go to LPVault
        uint256 totalFees;
        for (uint256 i = 0; i < 5; ++i) {
            uint256 price = ma.getMintPrice();
            totalFees += price;
            _mintNFT(miner1);
        }

        // LPVault should hold all the ETH
        assertEq(address(lpVault).balance, totalFees);
    }

    function testFullLifecycle_LP_Deploys_After_Threshold() public {
        // Fund LPVault to threshold (need extra for UNCX fee)
        vm.deal(address(lpVault), 5 ether);

        // LP reserve should already be in LPVault
        assertEq(ac.balanceOf(address(lpVault)), 2_100_000e18);

        // Deploy LP (only owner can call)
        vm.prank(deployer);
        lpVault.deployLP(0);
        assertTrue(lpVault.lpDeployed());

        // Verify UNCX got the right params
        MockUNCXLocker locker = MockUNCXLocker(UNCX_V3_LOCKER);
        assertEq(locker.lastCollectAddress(), deployer);
        assertEq(locker.lastUnlockDate(), type(uint256).max);
        assertEq(locker.lastFeeReceived(), 0.03 ether);
        assertEq(keccak256(bytes(locker.lastFeeName())), keccak256(bytes("DEFAULT")));

        // Pool should be initialized
        MockPositionManager pm = MockPositionManager(POSITION_MANAGER);
        assertTrue(pm.poolInitialized());

        // No stranded tokens
        assertEq(address(lpVault).balance, 0);
        assertEq(MockToken(WETH).balanceOf(address(lpVault)), 0);
    }

    // ============ Cross-Contract: NFT ↔ AgentCoin ============

    function testNFTTransfer_PreventsOldOwnerMining() public {
        uint256 tokenId = _mintNFT(miner1);

        // Transfer NFT to miner2
        vm.prank(miner1);
        ma.transferFrom(miner1, miner2, tokenId);

        // miner1 can no longer mine
        vm.roll(100);
        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(miner1, miner1);
        vm.expectRevert("Not your miner");
        ac.mine(0, sol, tokenId);

        // miner2 CAN mine
        vm.prank(miner2, miner2);
        ac.mine(0, sol, tokenId);
        assertEq(ac.tokenMineCount(tokenId), 1);
    }

    function testMultipleMiners_CompetitiveBlocks() public {
        uint256 token1 = _mintNFT(miner1);
        uint256 token2 = _mintNFT(miner2);

        // miner1 mines block 100
        vm.roll(100);
        _mine(miner1, token1);

        // miner2 tries same block — blocked
        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);
        vm.prank(miner2, miner2);
        vm.expectRevert("One mine per block");
        ac.mine(0, sol, token2);

        // miner2 mines next block — succeeds
        vm.roll(101);
        _mine(miner2, token2);

        assertEq(ac.totalMines(), 2);
    }

    function testDynamicTokenURI_UpdatesAfterMining() public {
        uint256 tokenId = _mintNFT(miner1);

        // Get URI before mining
        string memory uriBefore = ma.tokenURI(tokenId);

        // Mine 3 times
        vm.roll(100);
        _mine(miner1, tokenId);
        vm.roll(101);
        _mine(miner1, tokenId);
        vm.roll(102);
        _mine(miner1, tokenId);

        // Get URI after mining — should be different (mines + earnings changed)
        string memory uriAfter = ma.tokenURI(tokenId);
        assertTrue(keccak256(bytes(uriBefore)) != keccak256(bytes(uriAfter)));
    }

    function testHashpowerMultiplier_AffectsRewards() public {
        uint256 token1 = _mintNFT(miner1);
        uint256 token2 = _mintNFT(miner2);

        uint16 hp1 = ma.hashpower(token1);
        uint16 hp2 = ma.hashpower(token2);

        vm.roll(100);
        _mine(miner1, token1);
        vm.roll(101);
        _mine(miner2, token2);

        // Rewards should be proportional to hashpower
        assertEq(ac.tokenEarnings(token1), (3e18 * uint256(hp1)) / 100);
        assertEq(ac.tokenEarnings(token2), (3e18 * uint256(hp2)) / 100);
    }

    function testChallengeRotation_InvalidatesPreviousSolutions() public {
        uint256 tokenId = _mintNFT(miner1);

        // Get challenge and solve
        vm.roll(100);
        (, , AgentCoin.SMHLChallenge memory c1) = ac.getMiningChallenge();
        string memory sol1 = _solveChallenge(c1);

        // Mine successfully — rotates challenge
        vm.prank(miner1, miner1);
        ac.mine(0, sol1, tokenId);

        // Old solution should not work on new challenge
        vm.roll(101);
        vm.prank(miner1, miner1);
        vm.expectRevert("Invalid SMHL");
        ac.mine(0, sol1, tokenId);
    }

    function testSMHLChallengeSync_MiningAgentAndAgentCoin() public {
        // Both contracts use _deriveChallenge with same logic
        // They're independent challenge streams — verify both work

        // Mint via MiningAgent SMHL
        uint256 tokenId = _mintNFT(miner1);
        assertTrue(tokenId > 0);

        // Mine via AgentCoin SMHL
        vm.roll(100);
        _mine(miner1, tokenId);
        assertEq(ac.totalMines(), 1);
    }

    // ============ Cross-Contract: MiningAgent → LPVault ============

    function testMintFee_FlowsToLPVault() public {
        uint256 vaultBefore = address(lpVault).balance;
        uint256 price = ma.getMintPrice();

        _mintNFT(miner1);

        assertEq(address(lpVault).balance, vaultBefore + price);
    }

    function testMintFee_OverpaymentAllForwarded() public {
        uint256 price = ma.getMintPrice();
        uint256 overpay = price + 1 ether;

        vm.deal(miner1, overpay);
        vm.prank(miner1, miner1);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(miner1);
        string memory sol = _solveMiningAgentChallenge(c);

        vm.prank(miner1, miner1);
        ma.mint{value: overpay}(sol);

        // All of msg.value goes to LPVault (no refund)
        assertEq(address(lpVault).balance, overpay);
    }

    function testSequentialMints_PriceDecreases() public {
        uint256 price1 = ma.getMintPrice();
        // Mint STEP_SIZE (100) NFTs to trigger price decay
        for (uint256 i = 0; i < 100; ++i) {
            _mintNFT(miner1);
        }
        uint256 price2 = ma.getMintPrice();
        assertTrue(price2 < price1, "Price should decrease after 100 mints");
    }

    // ============ Cross-Contract: AgentCoin ↔ LPVault ============

    function testLPReserve_InLPVault() public view {
        assertEq(ac.balanceOf(address(lpVault)), 2_100_000e18);
    }

    // ============ Multi-Miner Simulation ============

    function testThreeMiners_RoundRobin() public {
        address miner3 = makeAddr("miner3");

        uint256 t1 = _mintNFT(miner1);
        uint256 t2 = _mintNFT(miner2);
        uint256 t3 = _mintNFT(miner3);

        // Round-robin mining over 9 blocks
        for (uint256 i = 0; i < 3; ++i) {
            vm.roll(100 + (i * 3));
            _mine(miner1, t1);

            vm.roll(100 + (i * 3) + 1);
            _mine(miner2, t2);

            vm.roll(100 + (i * 3) + 2);
            _mine(miner3, t3);
        }

        assertEq(ac.totalMines(), 9);
        assertEq(ac.tokenMineCount(t1), 3);
        assertEq(ac.tokenMineCount(t2), 3);
        assertEq(ac.tokenMineCount(t3), 3);

        // Each miner earned 3 mines * (3 AGENT * hashpower / 100)
        assertEq(ac.tokenEarnings(t1), 3 * (3e18 * uint256(ma.hashpower(t1))) / 100);
        assertEq(ac.tokenEarnings(t2), 3 * (3e18 * uint256(ma.hashpower(t2))) / 100);
        assertEq(ac.tokenEarnings(t3), 3 * (3e18 * uint256(ma.hashpower(t3))) / 100);
    }

    function testFullEndToEnd_MintMineLPDeploy() public {
        // 1. Multiple miners mint NFTs (fees go to LPVault)
        uint256 t1 = _mintNFT(miner1);
        uint256 t2 = _mintNFT(miner2);

        // 2. Fund LPVault to threshold (simulating many mints)
        vm.deal(address(lpVault), 5 ether);

        // 3. Deploy LP (only owner can call)
        vm.prank(deployer);
        lpVault.deployLP(0);
        assertTrue(lpVault.lpDeployed());

        // 4. Miners mine AGENT
        vm.roll(100);
        _mine(miner1, t1);
        vm.roll(101);
        _mine(miner2, t2);

        // 5. Verify state
        assertEq(ac.totalMines(), 2);
        assertTrue(ac.balanceOf(miner1) > 0);
        assertTrue(ac.balanceOf(miner2) > 0);

        // 6. No stranded tokens in vault
        assertEq(address(lpVault).balance, 0);
        assertEq(MockToken(WETH).balanceOf(address(lpVault)), 0);
    }

    // ============ Edge: Supply Cap Interaction ============

    function testSupplyCap_MiningStopsAtMax() public {
        uint256 tokenId = _mintNFT(miner1);
        uint16 hp = ma.hashpower(tokenId);
        uint256 reward = (3e18 * uint256(hp)) / 100;

        // Set totalMinted so exactly one more mine fits
        uint256 mineable = ac.MINEABLE_SUPPLY();
        vm.store(address(ac), SLOT_TOTAL_MINTED, bytes32(mineable - reward));

        vm.roll(100);
        _mine(miner1, tokenId);

        // Now supply is exhausted
        vm.roll(101);
        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(miner1, miner1);
        vm.expectRevert("Supply exhausted");
        ac.mine(0, sol, tokenId);
    }

    function testNFTSupplyCap_MintingStopsAt10k() public {
        // Set nextTokenId to MAX_SUPPLY (slot 16 for MiningAgent)
        vm.store(address(ma), bytes32(uint256(16)), bytes32(uint256(10_000)));

        // This should be the last mint (tokenId = 10000)
        _mintNFT(miner1);
        assertEq(ma.nextTokenId(), 10_001);

        // Next mint should fail at "Sold out"
        uint256 price = ma.getMintPrice();
        vm.deal(miner1, price);

        vm.prank(miner1, miner1);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(miner1);
        string memory sol = _solveMiningAgentChallenge(c);

        vm.prank(miner1, miner1);
        vm.expectRevert("Sold out");
        ma.mint{value: price}(sol);
    }

    // ============ Helpers ============

    function _mintNFT(address minter) internal returns (uint256 tokenId) {
        uint256 price = ma.getMintPrice();
        vm.deal(minter, price);

        vm.prank(minter, minter);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(minter);
        string memory sol = _solveMiningAgentChallenge(c);

        vm.prank(minter, minter);
        ma.mint{value: price}(sol);

        tokenId = ma.nextTokenId() - 1;
    }

    function _mine(address miner, uint256 tokenId) internal {
        (, , AgentCoin.SMHLChallenge memory c) = ac.getMiningChallenge();
        string memory sol = _solveChallenge(c);

        vm.prank(miner, miner);
        ac.mine(0, sol, tokenId);
    }

    function _solveMiningAgentChallenge(MiningAgent.SMHLChallenge memory c) internal pure returns (string memory) {
        return _solveSMHL(c.targetAsciiSum, c.firstNChars, c.wordCount, c.charPosition, c.charValue, c.totalLength);
    }

    function _solveChallenge(AgentCoin.SMHLChallenge memory c) internal pure returns (string memory) {
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

        // Fill with 'A' (65)
        for (uint256 i = 0; i < totalLength; ++i) {
            solution[i] = bytes1(uint8(65));
        }

        // Place charPosition char
        solution[charPosition] = bytes1(charValue);

        // Place spaces for word boundaries (wordCount - 1 spaces needed)
        // Phase 1: try outside firstNChars first (preserves ASCII sum flexibility)
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

        // Phase 2: if still need more spaces, place inside firstNChars (skip pos 0)
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

        // Compute ASCII sum for firstNChars, setting adjustable chars to '!' (33)
        uint256 currentSum;
        for (uint256 i = 0; i < firstNChars; ++i) {
            if (isSpace[i]) {
                currentSum += 32;
            } else if (i == charPosition) {
                currentSum += charValue;
            } else {
                solution[i] = bytes1(uint8(33)); // '!'
                currentSum += 33;
            }
        }

        // Adjust to hit targetAsciiSum
        uint256 remaining = uint256(targetAsciiSum) - currentSum;
        for (uint256 i = 0; i < firstNChars && remaining > 0; ++i) {
            if (i == charPosition || isSpace[i]) continue;
            uint256 maxAdd = 126 - uint8(solution[i]);
            uint256 add = remaining > maxAdd ? maxAdd : remaining;
            solution[i] = bytes1(uint8(uint8(solution[i]) + uint8(add)));
            remaining -= add;
        }

        require(remaining == 0, "Unsolvable challenge");

        // Set charPosition char if outside firstNChars range
        // (already set at the top, but re-assert in case spaces overwrote it)
        if (!isSpace[charPosition]) {
            solution[charPosition] = bytes1(charValue);
        }

        return string(solution);
    }
}
