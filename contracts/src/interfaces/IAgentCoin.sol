// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAgentCoin {
    function tokenMineCount(uint256 tokenId) external view returns (uint256);

    function tokenEarnings(uint256 tokenId) external view returns (uint256);
}
