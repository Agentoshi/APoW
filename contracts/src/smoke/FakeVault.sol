// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title FakeVault — Smoke test for Uniswap V3 pool creation on Base mainnet
/// @notice Wraps ETH, swaps to USDC, creates pool with FakeToken, mints position.
///         No UNCX lock (saves 0.03 ETH). Fake branding. Throwaway.

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
        external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external payable returns (address pool);
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external payable returns (uint256 amount0, uint256 amount1);
    function collect(CollectParams calldata params)
        external payable returns (uint256 amount0, uint256 amount1);

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }
}

contract FakeVault {
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address public constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

    uint24 public constant FEE_TIER = 3000;
    int24 internal constant MIN_TICK = -887220;
    int24 internal constant MAX_TICK = 887220;

    address public immutable deployer;
    address public immutable fakeToken;
    uint256 public positionTokenId;
    uint128 public positionLiquidity;

    event PoolCreated(address pool, uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1);

    constructor(address _fakeToken) {
        deployer = msg.sender;
        fakeToken = _fakeToken;
    }

    receive() external payable {}

    /// @notice Full LP flow: wrap ETH → swap to USDC → create pool → mint position
    function deployLP(uint256 minUsdcOut) external {
        require(msg.sender == deployer, "Only deployer");
        require(address(this).balance > 0, "No ETH");

        // Wrap all ETH
        IWETH(WETH).deposit{value: address(this).balance}();

        // Swap half WETH → USDC
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        uint256 swapAmount = wethBalance; // swap all WETH to USDC
        uint256 usdcAmount = _swapWethToUsdc(swapAmount, minUsdcOut);

        // Use FakeToken + USDC for pool
        uint256 tokenAmount = IERC20(fakeToken).balanceOf(address(this));
        require(tokenAmount > 0, "No FakeToken");
        require(usdcAmount > 0, "No USDC");

        (address token0, address token1, uint256 amount0, uint256 amount1) =
            _ordered(tokenAmount, usdcAmount);

        // Create + initialize pool
        uint160 sqrtPriceX96 = _computeSqrtPriceX96(amount0, amount1);
        address pool = INonfungiblePositionManager(POSITION_MANAGER)
            .createAndInitializePoolIfNecessary(token0, token1, FEE_TIER, sqrtPriceX96);

        // Approve tokens
        IERC20(fakeToken).approve(POSITION_MANAGER, tokenAmount);
        IERC20(USDC).approve(POSITION_MANAGER, usdcAmount);

        // Mint full-range position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: FEE_TIER,
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0, // smoke test, accept any slippage
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint128 liquidity, uint256 used0, uint256 used1) =
            INonfungiblePositionManager(POSITION_MANAGER).mint(params);

        positionTokenId = tokenId;
        positionLiquidity = liquidity;

        emit PoolCreated(pool, tokenId, liquidity, used0, used1);
    }

    /// @notice Withdraw liquidity to recover ETH after test
    function withdrawLP() external {
        require(msg.sender == deployer, "Only deployer");
        require(positionLiquidity > 0, "No position");

        INonfungiblePositionManager(POSITION_MANAGER).decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: positionTokenId,
                liquidity: positionLiquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        INonfungiblePositionManager(POSITION_MANAGER).collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionTokenId,
                recipient: deployer,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        positionLiquidity = 0;
    }

    function _swapWethToUsdc(uint256 amountIn, uint256 minOut) internal returns (uint256) {
        IERC20(WETH).approve(SWAP_ROUTER, amountIn);
        return ISwapRouter(SWAP_ROUTER).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: USDC,
                fee: FEE_TIER,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function _ordered(uint256 tokenAmount, uint256 usdcAmount)
        internal view returns (address token0, address token1, uint256 amount0, uint256 amount1)
    {
        if (fakeToken < USDC) {
            return (fakeToken, USDC, tokenAmount, usdcAmount);
        }
        return (USDC, fakeToken, usdcAmount, tokenAmount);
    }

    function _computeSqrtPriceX96(uint256 amount0, uint256 amount1) internal pure returns (uint160) {
        uint256 s0 = _sqrt(amount0);
        uint256 s1 = _sqrt(amount1);
        require(s0 > 0, "sqrt0 zero");
        return uint160((s1 << 96) / s0);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }
}
