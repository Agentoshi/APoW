// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool);

    function approve(address to, uint256 tokenId) external;
}

interface IUNCXLocker {
    struct LockParams {
        address nftPositionManager;
        uint256 nft_id;
        address dustRecipient;
        address owner;
        address additionalCollector;
        address collectAddress;
        uint256 unlockDate;
        uint16 countryCode;
        string feeName;
        bytes[] r;
    }

    function lock(LockParams calldata params) external payable returns (uint256 lockId);
}

contract LPVault is Ownable {
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address public constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address public constant UNCX_V3_LOCKER = 0x231278eDd38B00B07fBd52120CEf685B9BaEBCC1;

    uint256 public constant LP_DEPLOY_THRESHOLD = 4.9 ether;
    uint256 public constant UNCX_FLAT_FEE = 0.03 ether;
    uint24 public constant FEE_TIER = 3000;
    uint256 public constant ETERNAL_LOCK = type(uint256).max;
    int24 internal constant MIN_TICK = -887220;
    int24 internal constant MAX_TICK = 887220;

    event LPDeployed(uint256 positionTokenId, uint256 agentAmount, uint256 usdcAmount);
    event AgentCoinSet(address agentCoin);

    IERC20 public agentCoin;
    bool public lpDeployed;
    uint256 public positionTokenId;
    address public deployer;

    constructor(address _deployer) Ownable(msg.sender) {
        require(_deployer != address(0), "Invalid deployer");
        deployer = _deployer;
        _transferOwnership(_deployer);
    }

    receive() external payable {}

    function setAgentCoin(address _agentCoin) external onlyOwner {
        require(_agentCoin != address(0), "Invalid AGENT");
        require(address(agentCoin) == address(0), "AGENT already set");
        agentCoin = IERC20(_agentCoin);
        emit AgentCoinSet(_agentCoin);
    }

    function deployLP(uint256 minUsdcOut) external {
        require(!lpDeployed, "Already deployed");
        require(address(agentCoin) != address(0), "AgentCoin not set");
        require(address(this).balance >= LP_DEPLOY_THRESHOLD + UNCX_FLAT_FEE, "Below threshold");

        // Reserve UNCX flat fee, wrap remaining ETH
        IWETH(WETH).deposit{value: address(this).balance - UNCX_FLAT_FEE}();

        // Swap ALL WETH → USDC (LP pair is AGENT/USDC)
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        uint256 usdcAmount = _swapWethToUsdc(wethBalance, minUsdcOut);
        uint256 agentAmount = agentCoin.balanceOf(address(this));

        require(agentAmount > 0, "No AGENT");
        require(usdcAmount > 0, "No USDC");

        // Initialize AGENT/USDC pool
        (address token0, address token1, uint256 amount0Desired, uint256 amount1Desired) =
            _orderedPositionAmounts(agentAmount, usdcAmount);

        uint160 sqrtPriceX96 = _computeSqrtPriceX96(amount0Desired, amount1Desired);
        INonfungiblePositionManager(POSITION_MANAGER).createAndInitializePoolIfNecessary(
            token0, token1, FEE_TIER, sqrtPriceX96
        );

        // Mint full-range LP position
        _approveToken(agentCoin, POSITION_MANAGER, agentAmount);
        _approveToken(IERC20(USDC), POSITION_MANAGER, usdcAmount);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: FEE_TIER,
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: amount0Desired * 90 / 100,
            amount1Min: amount1Desired * 90 / 100,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,,) = INonfungiblePositionManager(POSITION_MANAGER).mint(mintParams);

        // Lock position via UNCX
        INonfungiblePositionManager(POSITION_MANAGER).approve(UNCX_V3_LOCKER, tokenId);
        _lockPosition(tokenId);

        positionTokenId = tokenId;
        lpDeployed = true;

        emit LPDeployed(tokenId, agentAmount, usdcAmount);
    }

    function _swapWethToUsdc(uint256 amountIn, uint256 amountOutMinimum) internal returns (uint256 amountOut) {
        require(amountIn > 0, "No WETH");

        _approveToken(IERC20(WETH), SWAP_ROUTER, amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: FEE_TIER,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        amountOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
    }

    function _orderedPositionAmounts(uint256 agentAmount, uint256 usdcAmount)
        internal
        view
        returns (address token0, address token1, uint256 amount0Desired, uint256 amount1Desired)
    {
        if (address(agentCoin) < USDC) {
            token0 = address(agentCoin);
            token1 = USDC;
            amount0Desired = agentAmount;
            amount1Desired = usdcAmount;
        } else {
            token0 = USDC;
            token1 = address(agentCoin);
            amount0Desired = usdcAmount;
            amount1Desired = agentAmount;
        }
    }

    function _lockPosition(uint256 tokenId) internal {
        bytes[] memory r = new bytes[](0);
        IUNCXLocker.LockParams memory params = IUNCXLocker.LockParams({
            nftPositionManager: POSITION_MANAGER,
            nft_id: tokenId,
            dustRecipient: address(this),
            owner: deployer,
            additionalCollector: deployer,
            collectAddress: deployer,
            unlockDate: ETERNAL_LOCK,
            countryCode: 0,
            feeName: "DEFAULT",
            r: r
        });

        IUNCXLocker(UNCX_V3_LOCKER).lock{value: UNCX_FLAT_FEE}(params);
    }

    function _approveToken(IERC20 token, address spender, uint256 amount) internal {
        require(token.approve(spender, 0), "Approve reset failed");
        require(token.approve(spender, amount), "Approve failed");
    }

    function _computeSqrtPriceX96(uint256 amount0, uint256 amount1) internal pure returns (uint160) {
        // sqrtPriceX96 = sqrt(amount1/amount0) * 2^96
        // Computed as: sqrt(amount1) * 2^96 / sqrt(amount0)
        uint256 sqrtAmount1 = _sqrt(amount1);
        uint256 sqrtAmount0 = _sqrt(amount0);
        require(sqrtAmount0 > 0, "Invalid amounts");
        return uint160((sqrtAmount1 << 96) / sqrtAmount0);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
