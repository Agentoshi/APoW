// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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
        return address(0);
    }
}

// ============ Renounce Immutability Tests ============

contract RenounceImmutabilityTest is Test {
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

    function _deployLP() internal {
        vm.deal(address(lpVault), 5 ether);
        vm.prank(deployer);
        lpVault.deployLP(0);
    }

    function _renounceAll() internal {
        vm.startPrank(deployer);
        ma.renounceOwnership();
        ac.renounceOwnership();
        lpVault.renounceOwnership();
        vm.stopPrank();
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
        if (!isSpace[charPosition]) {
            solution[charPosition] = bytes1(charValue);
        }

        return string(solution);
    }

    // ============ Test 1: Full Lifecycle ============

    function testFullLifecycle_DeployLP_RenounceAll_Immutable() public {
        // 1. Mint an NFT
        uint256 tokenId = _mintNFT(miner1);
        assertEq(ma.ownerOf(tokenId), miner1);

        // 2. Mine 1 block
        vm.roll(100);
        _mine(miner1, tokenId);
        assertEq(ac.totalMines(), 1);
        assertTrue(ac.balanceOf(miner1) > 0);

        // 3. Deploy LP
        _deployLP();
        assertTrue(lpVault.lpDeployed());

        // 4. Renounce ownership on all 3 contracts
        _renounceAll();
        assertEq(ma.owner(), address(0));
        assertEq(ac.owner(), address(0));
        assertEq(lpVault.owner(), address(0));

        // 5. Mine again — mining still works after renounce
        vm.roll(101);
        _mine(miner1, tokenId);
        assertEq(ac.totalMines(), 2);

        // 6. Verify immutability — owner is address(0) on all contracts
        assertEq(ma.owner(), address(0));
        assertEq(ac.owner(), address(0));
        assertEq(lpVault.owner(), address(0));
    }

    // ============ Test 2: All onlyOwner Functions Revert ============

    function testPostRenounce_AllOnlyOwnerFunctions_Revert() public {
        // Setup: deploy LP and renounce
        _deployLP();
        _renounceAll();

        // Verify all 3 owners are address(0)
        assertEq(ma.owner(), address(0));
        assertEq(ac.owner(), address(0));
        assertEq(lpVault.owner(), address(0));

        // --- MiningAgent onlyOwner functions ---

        // setLPVault reverts (deployer is no longer owner)
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, deployer));
        ma.setLPVault(payable(address(1)));

        // setAgentCoin reverts
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, deployer));
        ma.setAgentCoin(address(1));

        // --- LPVault onlyOwner functions ---

        // deployLP reverts
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, deployer));
        lpVault.deployLP(0);

        // emergencyUnwrapWeth reverts
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, deployer));
        lpVault.emergencyUnwrapWeth();

        // setAgentCoin on LPVault reverts
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, deployer));
        lpVault.setAgentCoin(address(1));

        // Also verify a random address can't call them either
        address rando = makeAddr("rando");

        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, rando));
        ma.setLPVault(payable(address(1)));

        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, rando));
        lpVault.deployLP(0);
    }

    // ============ Test 3: User Functions Still Work ============

    function testPostRenounce_UserFunctions_StillWork() public {
        // Setup: mint NFT, deploy LP, renounce
        uint256 tokenId = _mintNFT(miner1);
        _deployLP();
        _renounceAll();

        // Mint a new NFT — still works
        uint256 tokenId2 = _mintNFT(miner2);
        assertEq(ma.ownerOf(tokenId2), miner2);

        // Mine — still works
        vm.roll(100);
        _mine(miner1, tokenId);
        uint256 miner1Balance = ac.balanceOf(miner1);
        assertTrue(miner1Balance > 0);

        // Transfer AGENT tokens — still works (LP deployed so transfers are unlocked)
        uint256 transferAmount = miner1Balance / 2;
        vm.prank(miner1);
        ac.transfer(miner2, transferAmount);
        assertEq(ac.balanceOf(miner2), transferAmount);
        assertEq(ac.balanceOf(miner1), miner1Balance - transferAmount);

        // Transfer NFT — still works
        vm.prank(miner1);
        ma.transferFrom(miner1, miner2, tokenId);
        assertEq(ma.ownerOf(tokenId), miner2);
    }

    // ============ Test 4: Renounce Before LP Deploy Bricks Protocol ============

    function testRenounceBeforeLPDeploy_BricksProtocol() public {
        // Mint an NFT (fees go to LPVault)
        _mintNFT(miner1);

        // Renounce WITHOUT deploying LP first
        _renounceAll();

        // Verify owners are address(0)
        assertEq(ma.owner(), address(0));
        assertEq(ac.owner(), address(0));
        assertEq(lpVault.owner(), address(0));

        // Fund LPVault to threshold
        vm.deal(address(lpVault), 5 ether);

        // Try to deploy LP — reverts because onlyOwner and owner is address(0)
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, deployer));
        lpVault.deployLP(0);

        // Even from any other address — still reverts
        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, anyone));
        lpVault.deployLP(0);

        // Protocol is bricked: LP can never be deployed, transfers stay locked forever
        assertFalse(lpVault.lpDeployed());
    }

    // ============ Test 5: Deployer Retains Fee Collection Rights ============

    function testPostRenounce_DeployerRetainsFeeCollectionRights() public {
        // Setup: deploy LP and renounce
        _deployLP();
        _renounceAll();

        // Verify ownership is renounced
        assertEq(lpVault.owner(), address(0));

        // Verify deployer address is preserved in lpVault.deployer()
        // This is the UNCX collectAddress — fee collection rights survive renounce
        assertEq(lpVault.deployer(), deployer);

        // Verify UNCX locker recorded the deployer as collectAddress
        MockUNCXLocker locker = MockUNCXLocker(UNCX_V3_LOCKER);
        assertEq(locker.lastCollectAddress(), deployer);

        // deployer() is a public immutable-like storage variable, not gated by onlyOwner
        // so it remains accessible and unchanged even after ownership renunciation
        assertTrue(lpVault.deployer() != address(0));
        assertEq(lpVault.deployer(), deployer);
    }
}
