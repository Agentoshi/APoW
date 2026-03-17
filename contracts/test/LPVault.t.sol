// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {
    INonfungiblePositionManager,
    ISwapRouter,
    IUNCXLocker,
    LPVault
} from "../src/LPVault.sol";

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
        liquidity = uint128(_min(amount0, amount1));
    }

    function approve(address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == msg.sender, "Not owner");
        getApproved[tokenId] = to;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract MockUNCXLocker {
    uint256 public lastLockedTokenId;
    address public lastCollectAddress;
    uint256 public lastFeeReceived;
    string public lastFeeName;

    function lock(IUNCXLocker.LockParams calldata params) external payable returns (uint256) {
        lastLockedTokenId = params.nft_id;
        lastCollectAddress = params.collectAddress;
        lastFeeReceived = msg.value;
        lastFeeName = params.feeName;
        return 1;
    }
}

contract LPVaultTest is Test {
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address internal constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address internal constant UNCX_V3_LOCKER = 0x231278eDd38B00B07fBd52120CEf685B9BaEBCC1;

    LPVault internal lpVault;
    MockToken internal agentCoin;

    address internal deployer = makeAddr("deployer");
    address internal sender = makeAddr("sender");

    function setUp() public {
        vm.etch(WETH, address(new MockToken()).code);
        vm.etch(USDC, address(new MockToken()).code);
        vm.etch(SWAP_ROUTER, address(new MockSwapRouter()).code);
        vm.etch(POSITION_MANAGER, address(new MockPositionManager()).code);
        vm.etch(UNCX_V3_LOCKER, address(new MockUNCXLocker()).code);

        lpVault = new LPVault(deployer);
        agentCoin = new MockToken();

        vm.prank(deployer);
        lpVault.setAgentCoin(address(agentCoin));
    }

    function testReceiveETH() public {
        vm.deal(sender, 1 ether);

        vm.prank(sender, sender);
        (bool success,) = address(lpVault).call{value: 1 ether}("");

        assertTrue(success);
        assertEq(address(lpVault).balance, 1 ether);
    }

    function testDeployLPBelowThreshold() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 4 ether);

        vm.expectRevert("Below threshold");
        lpVault.deployLP(0);
    }

    function testDeployLPTwice() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);

        assertTrue(lpVault.lpDeployed());
        assertEq(lpVault.positionTokenId(), 1);

        vm.expectRevert("Already deployed");
        lpVault.deployLP(0);
    }

    function testDeployLP_UNCXFeeAndFeeName() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);

        MockUNCXLocker locker = MockUNCXLocker(UNCX_V3_LOCKER);
        assertEq(locker.lastFeeReceived(), 0.03 ether);
        assertEq(keccak256(bytes(locker.lastFeeName())), keccak256(bytes("DEFAULT")));
    }

    function testDeployLP_PoolInitialized() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);

        MockPositionManager pm = MockPositionManager(POSITION_MANAGER);
        assertTrue(pm.poolInitialized());
    }

    function testDeployLP_NoStrandedTokens() public {
        agentCoin.mint(address(lpVault), 2_100_000e18);
        vm.deal(address(lpVault), 5 ether);

        lpVault.deployLP(0);

        assertEq(address(lpVault).balance, 0);
        assertEq(MockToken(WETH).balanceOf(address(lpVault)), 0);
        assertEq(MockToken(USDC).balanceOf(address(lpVault)), 0);
        assertEq(agentCoin.balanceOf(address(lpVault)), 0);
    }
}
