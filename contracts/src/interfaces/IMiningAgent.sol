// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IMiningAgent is IERC721 {
    function hashpower(uint256 tokenId) external view returns (uint16);
}
