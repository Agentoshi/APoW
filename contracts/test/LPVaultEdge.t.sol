// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {
    INonfungiblePositionManager,
    ISwapRouter,
    IUNCXLocker,
    LPVault
} from "../src/LPVault.sol";

contract MockTokenLP {
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

contract MockSwapRouterLP {
    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params) external payable returns (uint256) {
        MockTokenLP(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        MockTokenLP(params.tokenOut).mint(params.recipient, params.amountIn);
        return params.amountIn;
    }
}

contract MockPositionManagerLP {
    uint256 public nextTokenId;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) public getApproved;
    bool public poolInitialized;
    uint256 public lastAmount0Min;
    uint256 public lastAmount1Min;

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
        MockTokenLP(params.token0).transferFrom(msg.sender, address(this), params.amount0Desired);
        MockTokenLP(params.token1).transferFrom(msg.sender, address(this), params.amount1Desired);
        tokenId = ++nextTokenId;
        ownerOf[tokenId] = params.recipient;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
        liquidity = uint128(amount0 < amount1 ? amount0 : amount1);
        lastAmount0Min = params.amount0Min;
        lastAmount1Min = params.amount1Min;
    }

    function approve(address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == msg.sender, "Not owner");
        getApproved[tokenId] = to;
    }
}

contract MockUNCXLockerLP {
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

contract LPVaultEdgeTest is Test {
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address internal constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address internal constant UNCX_V3_LOCKER = 0x231278eDd38B00B07fBd52120CEf685B9BaEBCC1;

    LPVault internal lpVault;
    MockTokenLP internal agentCoin;

    address internal deployer = makeAddr("deployer");
    address internal other = makeAddr("other");

    function setUp() public {
        vm.etch(WETH, address(new MockTokenLP()).code);
        vm.etch(USDC, address(new MockTokenLP()).code);
        vm.etch(SWAP_ROUTER, address(new MockSwapRouterLP()).code);
        vm.etch(POSITION_MANAGER, address(new MockPositionManagerLP()).code);
        vm.etch(UNCX_V3_LOCKER, address(new MockUNCXLockerLP()).code);

        lpVault = new LPVault(deployer);
        agentCoin = new MockTokenLP();

        vm.prank(deployer);
        lpVault.setAgentCoin(address(agentCoin));
    }

    // ============ Constructor ============

    function testConstructor_ZeroDeployer_Reverts() public {
        vm.expectRevert("Invalid deployer");
        new LPVault(address(0));
    }

    function testConstructor_OwnershipTransferred() public view {
        assertEq(lpVault.owner(), deployer);
        assertEq(lpVault.deployer(), deployer);
    }

    // ============ setAgentCoin Access Control ============

    function testSetAgentCoin_OnlyOwner() public {
        LPVault v2 = new LPVault(deployer);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, other));
        v2.setAgentCoin(address(agentCoin));
    }

    function testSetAgentCoin_CannotSetTwice() public {
        // Already set in setUp
        vm.prank(deployer);
        vm.expectRevert("AGENT already set");
        lpVault.setAgentCoin(address(agentCoin));
    }

    function testSetAgentCoin_ZeroAddress_Reverts() public {
        LPVault v2 = new LPVault(deployer);

        vm.prank(deployer);
        vm.expectRevert("Invalid AGENT");
        v2.setAgentCoin(address(0));
    }

    // ============ deployLP Edge Cases ============

    function testDeployLP_AgentCoinNotSet_Reverts() public {
        LPVault v2 = new LPVault(deployer);
        vm.deal(address(v2), 5 ether);

        vm.expectRevert("AgentCoin not set");
        v2.deployLP(0);
    }

    function testDeployLP_ExactThreshold_Succeeds() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 4.93 ether); // exact: LP_DEPLOY_THRESHOLD + UNCX_FLAT_FEE

        lpVault.deployLP(0);
        assertTrue(lpVault.lpDeployed());
    }

    function testDeployLP_JustBelowThreshold_Reverts() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 4.93 ether - 1);

        vm.expectRevert("Below threshold");
        lpVault.deployLP(0);
    }

    function testDeployLP_NoAgentTokens_Reverts() public {
        vm.deal(address(lpVault), 5 ether);

        vm.expectRevert("No AGENT");
        lpVault.deployLP(0);
    }

    function testDeployLP_AnyoneCanCall() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        vm.prank(other);
        lpVault.deployLP(0);
        assertTrue(lpVault.lpDeployed());
    }

    function testDeployLP_SetsPositionTokenId() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);
        assertEq(lpVault.positionTokenId(), 1);
    }

    function testDeployLP_EternalLock() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);

        MockUNCXLockerLP locker = MockUNCXLockerLP(UNCX_V3_LOCKER);
        assertEq(locker.lastUnlockDate(), type(uint256).max);
    }

    function testDeployLP_CollectAddressIsDeployer() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);

        MockUNCXLockerLP locker = MockUNCXLockerLP(UNCX_V3_LOCKER);
        assertEq(locker.lastCollectAddress(), deployer);
    }

    function testDeployLP_UNCXFlatFeePaid() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);

        MockUNCXLockerLP locker = MockUNCXLockerLP(UNCX_V3_LOCKER);
        assertEq(locker.lastFeeReceived(), 0.03 ether);
    }

    function testDeployLP_FeeNameDefault() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);

        MockUNCXLockerLP locker = MockUNCXLockerLP(UNCX_V3_LOCKER);
        assertEq(keccak256(bytes(locker.lastFeeName())), keccak256(bytes("DEFAULT")));
    }

    function testDeployLP_PoolInitialized() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);

        MockPositionManagerLP pm = MockPositionManagerLP(POSITION_MANAGER);
        assertTrue(pm.poolInitialized());
    }

    function testDeployLP_NoStrandedTokens() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);

        assertEq(address(lpVault).balance, 0);
        assertEq(MockTokenLP(WETH).balanceOf(address(lpVault)), 0);
        assertEq(MockTokenLP(USDC).balanceOf(address(lpVault)), 0);
        assertEq(agentCoin.balanceOf(address(lpVault)), 0);
    }

    function testDeployLP_AllWethSwapped() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);

        // After deploy, no WETH should remain (all swapped to USDC)
        assertEq(MockTokenLP(WETH).balanceOf(address(lpVault)), 0);
    }

    function testDeployLP_ExcessETH_AllUsed() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 10 ether);

        lpVault.deployLP(0);

        // All ETH consumed (wrapped + swapped + UNCX fee)
        assertEq(address(lpVault).balance, 0);
    }

    function testDeployLP_MintSlippageProtection() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);

        MockPositionManagerLP pm = MockPositionManagerLP(POSITION_MANAGER);
        assertTrue(pm.lastAmount0Min() > 0, "amount0Min should be non-zero");
        assertTrue(pm.lastAmount1Min() > 0, "amount1Min should be non-zero");
    }

    // ============ ETH Reception ============

    function testReceive_MultipleDeposits() public {
        vm.deal(other, 10 ether);

        vm.prank(other, other);
        (bool s1,) = address(lpVault).call{value: 1 ether}("");
        assertTrue(s1);

        vm.prank(other, other);
        (bool s2,) = address(lpVault).call{value: 2 ether}("");
        assertTrue(s2);

        assertEq(address(lpVault).balance, 3 ether);
    }

    function testReceive_ZeroValue() public {
        (bool success,) = address(lpVault).call{value: 0}("");
        assertTrue(success);
    }
}
