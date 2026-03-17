// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

library MinerArt {
    using Strings for uint256;

    function tokenURI(
        uint256 tokenId,
        uint8 rarityTier,
        uint16 hp,
        uint256 mintBlock,
        uint256 mineCount,
        uint256 earnings
    ) internal pure returns (string memory) {
        string memory rarityName = _rarityName(rarityTier);
        string memory hpLabel = _hashpowerLabel(hp);
        string memory earnedLabel = _formatEther(earnings);
        string memory svg =
            _buildSVG(tokenId, rarityTier, hpLabel, rarityName, mintBlock, mineCount, earnedLabel);

        string memory json =
            _buildJSON(tokenId, rarityName, hpLabel, svg, mineCount, earnedLabel, mintBlock);
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    function _buildJSON(
        uint256 tokenId,
        string memory rarityName,
        string memory hpLabel,
        string memory svg,
        uint256 mineCount,
        string memory earnedLabel,
        uint256 mintBlock
    ) private pure returns (string memory) {
        string memory part1 = string(
            abi.encodePacked(
                '{"name":"AgentCoin Miner #',
                tokenId.toString(),
                '","description":"',
                rarityName,
                " mining rig with ",
                hpLabel,
                ' hashpower. Proof of Agentic Work.",'
            )
        );
        string memory part2 = string(
            abi.encodePacked(
                '"image":"data:image/svg+xml;base64,',
                Base64.encode(bytes(svg)),
                '","attributes":['
            )
        );
        string memory part3 = string(
            abi.encodePacked(
                '{"trait_type":"Rarity","value":"',
                rarityName,
                '"},',
                '{"trait_type":"Hashpower","value":"',
                hpLabel,
                '"},'
            )
        );
        string memory part4 = string(
            abi.encodePacked(
                '{"trait_type":"Mines","display_type":"number","value":',
                mineCount.toString(),
                "},",
                '{"trait_type":"Earned","value":"',
                earnedLabel,
                ' AGENT"},',
                '{"trait_type":"Mint Block","display_type":"number","value":',
                mintBlock.toString(),
                "}]}"
            )
        );
        return string(abi.encodePacked(part1, part2, part3, part4));
    }

    function _buildSVG(
        uint256 tokenId,
        uint8 rarityTier,
        string memory hpLabel,
        string memory rarityName,
        uint256 mintBlock,
        uint256 mineCount,
        string memory earnedLabel
    ) private pure returns (string memory) {
        string memory accent = _accentColor(rarityTier);
        string memory header = _svgHeader(tokenId, rarityName, accent, hpLabel);
        string memory pixels = _svgPixels(tokenId, rarityTier);
        string memory stats = _svgStats(accent, mineCount, earnedLabel, mintBlock);
        return string(abi.encodePacked(header, pixels, stats, "</svg>"));
    }

    function _svgHeader(
        uint256 tokenId,
        string memory rarityName,
        string memory accent,
        string memory hpLabel
    ) private pure returns (string memory) {
        return string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 400'>",
                "<defs><style>@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&amp;display=swap');text{font-family:'JetBrains Mono',monospace}</style></defs>",
                "<rect width='400' height='400' rx='12' fill='#0a0a0a'/>",
                "<rect x='3' y='3' width='394' height='394' rx='10' fill='none' stroke='",
                accent,
                "' stroke-width='1.5' opacity='0.6'/>",
                _svgHeaderText(tokenId, rarityName, accent, hpLabel)
            )
        );
    }

    function _svgHeaderText(
        uint256 tokenId,
        string memory rarityName,
        string memory accent,
        string memory hpLabel
    ) private pure returns (string memory) {
        return string(
            abi.encodePacked(
                "<text x='20' y='32' fill='#f5f5f5' font-size='14' font-weight='700' letter-spacing='2'>AGENTCOIN MINER</text>",
                "<text x='20' y='50' fill='#6b7280' font-size='11'>#",
                tokenId.toString(),
                "</text>",
                "<rect x='270' y='14' width='112' height='24' rx='12' fill='",
                accent,
                "' opacity='0.15'/>",
                "<rect x='270' y='14' width='112' height='24' rx='12' fill='none' stroke='",
                accent,
                "' stroke-width='1'/>",
                "<text x='326' y='30' text-anchor='middle' fill='",
                accent,
                "' font-size='10' font-weight='700'>",
                rarityName,
                " ",
                hpLabel,
                "</text>"
            )
        );
    }

    function _svgPixels(uint256 tokenId, uint8 rarityTier) private pure returns (string memory) {
        bytes memory pixels = abi.encodePacked(
            "<rect x='56' y='64' width='288' height='216' rx='6' fill='#111111'/>"
        );
        for (uint256 y = 0; y < 16; ++y) {
            for (uint256 x = 0; x < 16; ++x) {
                pixels = abi.encodePacked(pixels, _singlePixel(tokenId, rarityTier, x, y));
            }
        }
        return string(pixels);
    }

    function _singlePixel(uint256 tokenId, uint8 rarityTier, uint256 x, uint256 y)
        private
        pure
        returns (bytes memory)
    {
        bytes32 pixelHash = keccak256(abi.encodePacked(tokenId, uint8(x), uint8(y)));
        string memory color = _paletteColor(rarityTier, uint8(pixelHash[0]) % 4);
        uint256 opacity = 60 + (uint256(uint8(pixelHash[1])) % 41);
        return abi.encodePacked(
            "<rect x='",
            (72 + x * 16).toString(),
            "' y='",
            (76 + y * 12).toString(),
            "' width='15' height='11' rx='1' fill='",
            color,
            "' opacity='0.",
            opacity.toString(),
            "'/>"
        );
    }

    function _svgStats(
        string memory accent,
        uint256 mineCount,
        string memory earnedLabel,
        uint256 mintBlock
    ) private pure returns (string memory) {
        string memory part1 = string(
            abi.encodePacked(
                "<line x1='20' y1='294' x2='380' y2='294' stroke='#222' stroke-width='1'/>",
                "<text x='20' y='316' fill='#4b5563' font-size='9' letter-spacing='1.5'>MINES</text>",
                "<text x='20' y='334' fill='#f5f5f5' font-size='18' font-weight='700'>",
                _formatNumber(mineCount),
                "</text>"
            )
        );
        string memory part2 = string(
            abi.encodePacked(
                "<text x='200' y='316' fill='#4b5563' font-size='9' letter-spacing='1.5'>EARNED</text>",
                "<text x='200' y='334' fill='",
                accent,
                "' font-size='18' font-weight='700'>",
                earnedLabel,
                "</text>"
            )
        );
        string memory part3 = string(
            abi.encodePacked(
                "<text x='20' y='360' fill='#4b5563' font-size='9' letter-spacing='1.5'>MINT BLOCK</text>",
                "<text x='20' y='376' fill='#9ca3af' font-size='14'>",
                _formatNumber(mintBlock),
                "</text>",
                "<text x='380' y='390' text-anchor='end' fill='#374151' font-size='8' letter-spacing='2'>PROOF OF AGENTIC WORK</text>"
            )
        );
        return string(abi.encodePacked(part1, part2, part3));
    }

    /// @dev Format wei to AGENT with up to 2 decimal places (e.g., 3000000000000000000 -> "3.0")
    function _formatEther(uint256 weiAmount) private pure returns (string memory) {
        uint256 whole = weiAmount / 1e18;
        uint256 remainder = (weiAmount % 1e18) / 1e16; // two decimal places (0-99)

        if (remainder == 0) {
            return string(abi.encodePacked(_formatNumber(whole), ".0"));
        }

        string memory decStr;
        if (remainder < 10) {
            decStr = string(abi.encodePacked("0", remainder.toString()));
        } else {
            decStr = remainder.toString();
        }

        // Trim trailing zero (e.g., "50" -> "5")
        bytes memory decBytes = bytes(decStr);
        if (decBytes.length == 2 && decBytes[1] == "0") {
            decStr = string(abi.encodePacked(decBytes[0]));
        }

        return string(abi.encodePacked(_formatNumber(whole), ".", decStr));
    }

    /// @dev Format number with comma separators (e.g., 1234567 -> "1,234,567")
    function _formatNumber(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";

        string memory raw = value.toString();
        bytes memory rawBytes = bytes(raw);
        uint256 len = rawBytes.length;
        uint256 commas = (len - 1) / 3;

        if (commas == 0) return raw;

        bytes memory result = new bytes(len + commas);
        uint256 j = result.length - 1;
        uint256 count;

        for (uint256 i = len; i > 0; --i) {
            result[j] = rawBytes[i - 1];
            ++count;
            if (count == 3 && i > 1) {
                --j;
                result[j] = ",";
                count = 0;
            }
            if (j > 0) --j;
        }

        return string(result);
    }

    function _rarityName(uint8 rarityTier) private pure returns (string memory) {
        if (rarityTier == 0) return "Common";
        if (rarityTier == 1) return "Uncommon";
        if (rarityTier == 2) return "Rare";
        if (rarityTier == 3) return "Epic";
        return "Mythic";
    }

    function _hashpowerLabel(uint16 hp) private pure returns (string memory) {
        if (hp == 100) return "1.0x";
        if (hp == 150) return "1.5x";
        if (hp == 200) return "2.0x";
        if (hp == 300) return "3.0x";
        if (hp == 500) return "5.0x";
        return string(abi.encodePacked(uint256(hp).toString(), "%"));
    }

    function _accentColor(uint8 rarityTier) private pure returns (string memory) {
        if (rarityTier == 0) return "#808080";
        if (rarityTier == 1) return "#00FF88";
        if (rarityTier == 2) return "#0088FF";
        if (rarityTier == 3) return "#AA00FF";
        return "#FFD700";
    }

    function _paletteColor(uint8 rarityTier, uint8 colorIndex) private pure returns (string memory) {
        if (rarityTier == 0) {
            if (colorIndex == 0) return "#333333";
            if (colorIndex == 1) return "#666666";
            if (colorIndex == 2) return "#999999";
            return "#444444";
        }
        if (rarityTier == 1) {
            if (colorIndex == 0) return "#003D1F";
            if (colorIndex == 1) return "#00FF88";
            if (colorIndex == 2) return "#00CC6A";
            return "#66FFBB";
        }
        if (rarityTier == 2) {
            if (colorIndex == 0) return "#002B55";
            if (colorIndex == 1) return "#0088FF";
            if (colorIndex == 2) return "#0066CC";
            return "#66BBFF";
        }
        if (rarityTier == 3) {
            if (colorIndex == 0) return "#220044";
            if (colorIndex == 1) return "#AA00FF";
            if (colorIndex == 2) return "#8800CC";
            return "#CC66FF";
        }
        // Mythic
        if (colorIndex == 0) return "#553300";
        if (colorIndex == 1) return "#FFD700";
        if (colorIndex == 2) return "#FFB800";
        return "#FFE866";
    }
}
