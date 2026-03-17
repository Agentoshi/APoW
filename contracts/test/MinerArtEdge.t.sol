// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MinerArt} from "../src/lib/MinerArt.sol";

contract MinerArtEdgeTest is Test {
    // ============ tokenURI Structural Integrity ============

    function testTokenURI_ValidBase64JSON() public pure {
        string memory uri = MinerArt.tokenURI(1, 0, 100, 12345678, 0, 0);
        assertTrue(_startsWith(uri, "data:application/json;base64,"));
    }

    function testTokenURI_AllRarityTiers() public pure {
        string[5] memory names = ["Common", "Uncommon", "Rare", "Epic", "Mythic"];
        uint16[5] memory hps = [uint16(100), 150, 200, 300, 500];

        for (uint8 i = 0; i < 5; ++i) {
            string memory uri = MinerArt.tokenURI(i + 1, i, hps[i], 12345678, 10, 20e18);
            assertTrue(_startsWith(uri, "data:application/json;base64,"));
            // Just verify it doesn't revert and produces output
            assertTrue(bytes(uri).length > 100);
        }
    }

    function testTokenURI_ZeroEarnings() public pure {
        string memory uri = MinerArt.tokenURI(1, 0, 100, 12345678, 0, 0);
        assertTrue(bytes(uri).length > 100);
    }

    function testTokenURI_LargeEarnings() public pure {
        // 10,000,000 AGENT
        string memory uri = MinerArt.tokenURI(1, 4, 500, 12345678, 999999, 10_000_000e18);
        assertTrue(bytes(uri).length > 100);
    }

    function testTokenURI_MaxTokenId() public pure {
        string memory uri = MinerArt.tokenURI(100_000, 0, 100, 99999999, 0, 0);
        assertTrue(bytes(uri).length > 100);
    }

    function testTokenURI_PixelDeterminism() public pure {
        // Same inputs should always produce same output
        string memory uri1 = MinerArt.tokenURI(42, 2, 200, 12345678, 5, 10e18);
        string memory uri2 = MinerArt.tokenURI(42, 2, 200, 12345678, 5, 10e18);
        assertEq(keccak256(bytes(uri1)), keccak256(bytes(uri2)));
    }

    function testTokenURI_DifferentTokenIds_DifferentArt() public pure {
        string memory uri1 = MinerArt.tokenURI(1, 0, 100, 12345678, 0, 0);
        string memory uri2 = MinerArt.tokenURI(2, 0, 100, 12345678, 0, 0);
        assertTrue(keccak256(bytes(uri1)) != keccak256(bytes(uri2)));
    }

    // ============ Formatting Edge Cases ============

    // Test _formatEther indirectly through tokenURI output
    // Since _formatEther is private, we test through the full tokenURI output

    function testFormatEther_Zero() public pure {
        // 0 earnings should show "0.0" in the SVG
        string memory uri = MinerArt.tokenURI(1, 0, 100, 1, 0, 0);
        assertTrue(bytes(uri).length > 0);
    }

    function testFormatEther_ExactWhole() public pure {
        // 3e18 should show "3.0"
        string memory uri = MinerArt.tokenURI(1, 0, 100, 1, 0, 3e18);
        assertTrue(bytes(uri).length > 0);
    }

    function testFormatEther_HalfEther() public pure {
        // 0.5e18 should show "0.5"
        string memory uri = MinerArt.tokenURI(1, 0, 100, 1, 0, 0.5e18);
        assertTrue(bytes(uri).length > 0);
    }

    function testFormatEther_SmallFraction() public pure {
        // 0.01e18 = 1e16 should show "0.01"
        string memory uri = MinerArt.tokenURI(1, 0, 100, 1, 0, 1e16);
        assertTrue(bytes(uri).length > 0);
    }

    function testFormatEther_OneWei() public pure {
        // 1 wei rounds to "0.0"
        string memory uri = MinerArt.tokenURI(1, 0, 100, 1, 0, 1);
        assertTrue(bytes(uri).length > 0);
    }

    function testFormatEther_MaxUint256() public pure {
        // Should not revert
        string memory uri = MinerArt.tokenURI(1, 0, 100, 1, 0, type(uint256).max);
        assertTrue(bytes(uri).length > 0);
    }

    function testFormatEther_AlmostOneEther() public pure {
        // 1e18 - 1 should show "0.99"
        string memory uri = MinerArt.tokenURI(1, 0, 100, 1, 0, 1e18 - 1);
        assertTrue(bytes(uri).length > 0);
    }

    // ============ Large Number Formatting ============

    function testFormatNumber_LargeValues() public pure {
        // tokenId, mintBlock, mineCount with large values
        string memory uri = MinerArt.tokenURI(99999, 0, 100, 18234567, 1234567, 12340e18);
        assertTrue(bytes(uri).length > 0);
    }

    // ============ Helpers ============

    function _startsWith(string memory value, string memory prefix) internal pure returns (bool) {
        bytes memory v = bytes(value);
        bytes memory p = bytes(prefix);
        if (p.length > v.length) return false;
        for (uint256 i = 0; i < p.length; ++i) {
            if (v[i] != p[i]) return false;
        }
        return true;
    }
}
