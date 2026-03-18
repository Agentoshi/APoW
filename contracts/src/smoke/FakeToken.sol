// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title FakeToken — Smoke test for ERC20 transfer lock
/// @notice Minimal ERC20 with _update() lock identical to AgentCoin's pattern.
///         Fake branding. Deployed from throwaway wallet. Zero connection to AgentCoin.
contract FakeToken is ERC20 {
    address public immutable deployer;
    bool public transfersUnlocked;

    constructor() ERC20("TestAlpha", "TA") {
        deployer = msg.sender;
        _mint(msg.sender, 1_000_000e18);
    }

    function unlock() external {
        require(msg.sender == deployer, "Only deployer");
        require(!transfersUnlocked, "Already unlocked");
        transfersUnlocked = true;
    }

    function _update(address from, address to, uint256 value) internal override {
        // Allow minting (from == address(0))
        // Block all other transfers before unlock
        if (!transfersUnlocked && from != address(0)) {
            require(from == deployer, "Transfers locked");
        }
        super._update(from, to, value);
    }
}
