// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MiningAgent} from "../src/MiningAgent.sol";
import {IAgentCoin} from "../src/interfaces/IAgentCoin.sol";

contract MockAgentCoinForEdge is IAgentCoin {
    function tokenMineCount(uint256) external pure returns (uint256) { return 0; }
    function tokenEarnings(uint256) external pure returns (uint256) { return 0; }
    function setLPDeployed() external {}
}

// Contract caller to test tx.origin check
contract ContractCaller {
    function callGetChallenge(MiningAgent ma) external returns (MiningAgent.SMHLChallenge memory) {
        return ma.getChallenge(address(this));
    }

    function callMint(MiningAgent ma, string calldata solution) external payable {
        ma.mint{value: msg.value}(solution);
    }
}

// Rejecting vault to test fee forward failure
contract RejectingVault {
    receive() external payable {
        revert("rejected");
    }
}

// Reentrancy attacker vault
contract ReentrantVault {
    MiningAgent public target;
    bool public attacked;

    constructor(MiningAgent _target) {
        target = _target;
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            // Try to re-enter mint — should fail with "No challenge" since it's already deleted
            try target.mint{value: msg.value}("anything") {} catch {}
        }
    }
}

contract MiningAgentEdgeTest is Test {
    MiningAgent internal ma;
    MockAgentCoinForEdge internal mockAc;

    address internal user = makeAddr("user");
    address internal user2 = makeAddr("user2");
    address payable internal lpVault = payable(makeAddr("lpVault"));

    function setUp() public {
        ma = new MiningAgent();
        mockAc = new MockAgentCoinForEdge();
        ma.setLPVault(lpVault);
        ma.setAgentCoin(address(mockAc));
        vm.deal(user, 100 ether);
        vm.deal(user2, 100 ether);
    }

    // ============ Access Control ============

    function testMintFromContract_Reverts() public {
        ContractCaller caller = new ContractCaller();
        vm.deal(address(caller), 10 ether);

        vm.prevrandao(uint256(100));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory challenge = ma.getChallenge(user);

        // Even with a valid challenge, contract callers are blocked
        string memory solution = _solveChallenge(challenge);
        uint256 price = ma.getMintPrice();

        vm.prank(user); // msg.sender == user, but tx.origin will differ in contract context
        vm.expectRevert("No contracts");
        caller.callMint(ma, solution);
    }

    function testSetLPVault_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        ma.setLPVault(payable(user));
    }

    function testSetAgentCoin_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        ma.setAgentCoin(user);
    }

    function testSetLPVault_OwnerSucceeds() public {
        MiningAgent ma2 = new MiningAgent();
        address payable newVault = payable(makeAddr("newVault"));
        ma2.setLPVault(newVault);
        assertEq(ma2.lpVault(), newVault);
    }

    function testSetAgentCoin_OwnerSucceeds() public {
        MiningAgent ma2 = new MiningAgent();
        address newAc = makeAddr("newAc");
        ma2.setAgentCoin(newAc);
        assertEq(ma2.agentCoin(), newAc);
    }

    function testSetLPVault_AlreadySet_Reverts() public {
        vm.expectRevert("Already set");
        ma.setLPVault(payable(makeAddr("newVault")));
    }

    function testSetAgentCoin_AlreadySet_Reverts() public {
        vm.expectRevert("Already set");
        ma.setAgentCoin(makeAddr("newAc"));
    }

    function testSetLPVault_ZeroAddress_Reverts() public {
        MiningAgent ma2 = new MiningAgent();
        vm.expectRevert("Invalid LPVault");
        ma2.setLPVault(payable(address(0)));
    }

    function testSetAgentCoin_ZeroAddress_Reverts() public {
        MiningAgent ma2 = new MiningAgent();
        vm.expectRevert("Invalid AgentCoin");
        ma2.setAgentCoin(address(0));
    }

    function testGetChallenge_AnyoneCanCall() public {
        vm.prevrandao(uint256(200));
        // Even a contract can call getChallenge (no tx.origin check)
        ContractCaller caller = new ContractCaller();
        MiningAgent.SMHLChallenge memory c = caller.callGetChallenge(ma);
        assertTrue(c.totalLength >= 20);
    }

    // ============ Challenge Lifecycle & Timing ============

    function testMintWithNoChallenge_Reverts() public {
        uint256 price = ma.getMintPrice();
        vm.prank(user, user);
        vm.expectRevert("No challenge");
        ma.mint{value: price}("anything");
    }

    function testMintExactlyAtExpiryBoundary_Succeeds() public {
        vm.prevrandao(uint256(300));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        string memory solution = _solveChallenge(c);
        uint256 price = ma.getMintPrice();

        // Warp exactly to challenge timestamp + CHALLENGE_DURATION (20s)
        vm.warp(block.timestamp + 20);

        vm.prank(user, user);
        ma.mint{value: price}(solution);
        assertEq(ma.ownerOf(1), user);
    }

    function testMintOneSecondAfterExpiry_Reverts() public {
        vm.prevrandao(uint256(301));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        string memory solution = _solveChallenge(c);
        uint256 price = ma.getMintPrice();

        vm.warp(block.timestamp + 21);

        vm.prank(user, user);
        vm.expectRevert("Expired");
        ma.mint{value: price}(solution);
    }

    function testMintSameBlock_Succeeds() public {
        vm.prevrandao(uint256(302));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        string memory solution = _solveChallenge(c);
        uint256 price = ma.getMintPrice();

        // No warp — same block as getChallenge
        vm.prank(user, user);
        ma.mint{value: price}(solution);
        assertEq(ma.ownerOf(1), user);
    }

    function testDoubleMintSameChallenge_Reverts() public {
        vm.prevrandao(uint256(303));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        string memory solution = _solveChallenge(c);
        uint256 price = ma.getMintPrice();

        vm.prank(user, user);
        ma.mint{value: price}(solution);

        // Challenge is deleted — second mint should fail
        vm.prank(user, user);
        vm.expectRevert("No challenge");
        ma.mint{value: price}(solution);
    }

    function testGetChallengeOverwritesPrevious() public {
        vm.prevrandao(uint256(304));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c1 = ma.getChallenge(user);
        bytes32 seed1 = ma.challengeSeeds(user);

        vm.prevrandao(uint256(305));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c2 = ma.getChallenge(user);
        bytes32 seed2 = ma.challengeSeeds(user);

        assertTrue(seed1 != seed2);

        // Old challenge solution should not work
        string memory oldSolution = _solveChallenge(c1);
        uint256 price = ma.getMintPrice();

        // Only the latest challenge (c2) works
        string memory newSolution = _solveChallenge(c2);
        vm.prank(user, user);
        ma.mint{value: price}(newSolution);
        assertEq(ma.ownerOf(1), user);
    }

    function testChallengeNonceIncrements() public {
        uint256 nonce0 = ma.challengeNonce();
        vm.prevrandao(uint256(306));
        vm.prank(user, user);
        ma.getChallenge(user);
        assertEq(ma.challengeNonce(), nonce0 + 1);

        vm.prevrandao(uint256(307));
        vm.prank(user, user);
        ma.getChallenge(user);
        assertEq(ma.challengeNonce(), nonce0 + 2);
    }

    function testTwoUsersChallengeIndependence() public {
        vm.prevrandao(uint256(308));

        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c1 = ma.getChallenge(user);

        vm.prank(user2, user2);
        MiningAgent.SMHLChallenge memory c2 = ma.getChallenge(user2);

        // Both can mint independently
        uint256 price = ma.getMintPrice();

        vm.prank(user, user);
        ma.mint{value: price}(_solveChallenge(c1));

        vm.prank(user2, user2);
        ma.mint{value: price}(_solveChallenge(c2));

        assertEq(ma.ownerOf(1), user);
        assertEq(ma.ownerOf(2), user2);
    }

    // ============ SMHL Verification Edge Cases ============

    function testSMHL_WrongTotalLength_TooShort() public {
        vm.prevrandao(uint256(400));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        uint256 price = ma.getMintPrice();

        // Create solution that's 10 chars too short (beyond ±5 tolerance)
        uint256 shortLen = c.totalLength > 10 ? c.totalLength - 10 : 1;
        bytes memory shortSol = new bytes(shortLen);
        for (uint256 i = 0; i < shortSol.length; ++i) shortSol[i] = bytes1(c.charValue);

        vm.prank(user, user);
        vm.expectRevert("Invalid SMHL");
        ma.mint{value: price}(string(shortSol));
    }

    function testSMHL_WrongTotalLength_TooLong() public {
        vm.prevrandao(uint256(401));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        uint256 price = ma.getMintPrice();

        // Create solution that's 10 chars too long (beyond ±5 tolerance)
        bytes memory longSol = new bytes(c.totalLength + 10);
        for (uint256 i = 0; i < longSol.length; ++i) longSol[i] = bytes1(c.charValue);

        vm.prank(user, user);
        vm.expectRevert("Invalid SMHL");
        ma.mint{value: price}(string(longSol));
    }

    function testSMHL_EmptyString() public {
        vm.prevrandao(uint256(402));
        vm.prank(user, user);
        ma.getChallenge(user);
        uint256 price = ma.getMintPrice();

        vm.prank(user, user);
        vm.expectRevert("Invalid SMHL");
        ma.mint{value: price}("");
    }

    function testSMHL_MissingRequiredChar() public {
        vm.prevrandao(uint256(403));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        string memory solution = _solveChallenge(c);
        uint256 price = ma.getMintPrice();

        // Replace ALL occurrences of the required char with a different one
        bytes memory tampered = bytes(solution);
        uint8 replacement = c.charValue == 97 ? 98 : 97;
        for (uint256 i = 0; i < tampered.length; ++i) {
            if (uint8(tampered[i]) == c.charValue) {
                tampered[i] = bytes1(replacement);
            }
        }

        vm.prank(user, user);
        vm.expectRevert("Invalid SMHL");
        ma.mint{value: price}(string(tampered));
    }

    function testSMHL_WrongWordCount() public {
        vm.prevrandao(uint256(405));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        uint256 price = ma.getMintPrice();

        // Build solution with correct length and required char, but way too many words
        // Alternate char and space: "a a a a ..." gives totalLength/2 words
        bytes memory tampered = new bytes(c.totalLength);
        for (uint256 i = 0; i < c.totalLength; ++i) {
            tampered[i] = (i % 2 == 0) ? bytes1(c.charValue) : bytes1(uint8(32));
        }
        // Ensure last char is not a space
        tampered[c.totalLength - 1] = bytes1(c.charValue);

        vm.prank(user, user);
        vm.expectRevert("Invalid SMHL");
        ma.mint{value: price}(string(tampered));
    }

    function testSMHL_LeadingSpaces() public {
        vm.prevrandao(uint256(407));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        uint256 price = ma.getMintPrice();

        // Build all-space string of correct length
        bytes memory spacey = new bytes(c.totalLength);
        for (uint256 i = 0; i < c.totalLength; ++i) spacey[i] = " ";

        vm.prank(user, user);
        vm.expectRevert("Invalid SMHL");
        ma.mint{value: price}(string(spacey));
    }

    // ============ Payment Edge Cases ============

    function testMintInsufficientFee_Reverts() public {
        vm.prevrandao(uint256(500));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        string memory solution = _solveChallenge(c);
        uint256 price = ma.getMintPrice();

        vm.prank(user, user);
        vm.expectRevert("Insufficient fee");
        ma.mint{value: price - 1}(solution);
    }

    function testMintOverpayment_ForwardsAll() public {
        vm.prevrandao(uint256(501));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        string memory solution = _solveChallenge(c);
        uint256 price = ma.getMintPrice();
        uint256 overpay = price + 0.01 ether;
        uint256 vaultBefore = lpVault.balance;

        vm.prank(user, user);
        ma.mint{value: overpay}(solution);

        // Full msg.value forwarded, not just price
        assertEq(lpVault.balance, vaultBefore + overpay);
    }

    function testMintZeroValue_Reverts() public {
        vm.prevrandao(uint256(502));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        string memory solution = _solveChallenge(c);

        vm.prank(user, user);
        vm.expectRevert("Insufficient fee");
        ma.mint{value: 0}(solution);
    }

    function testMintLPVaultNotSet_Reverts() public {
        MiningAgent ma2 = new MiningAgent();
        ma2.setAgentCoin(address(mockAc));
        // Don't set lpVault

        vm.prevrandao(uint256(503));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma2.getChallenge(user);
        string memory solution = _solveChallenge(c);

        vm.prank(user, user);
        vm.expectRevert("LPVault not set");
        ma2.mint{value: 0.002 ether}(solution);
    }

    function testMintFeeForwardToRejectingVault_Reverts() public {
        MiningAgent ma2 = new MiningAgent();
        RejectingVault rv = new RejectingVault();
        ma2.setLPVault(payable(address(rv)));
        ma2.setAgentCoin(address(mockAc));

        vm.prevrandao(uint256(504));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma2.getChallenge(user);
        string memory solution = _solveChallenge(c);

        vm.prank(user, user);
        vm.expectRevert("Fee forward failed");
        ma2.mint{value: 0.002 ether}(solution);
    }

    // ============ Pricing Boundaries ============

    function testGetMintPrice_BeforeFirstStep() public view {
        // nextTokenId = 1, minted = 0
        assertEq(ma.getMintPrice(), 0.002 ether);
    }

    function testGetMintPrice_AtFirstStepBoundary() public {
        // 100 minted: first step boundary
        bytes32 slot = bytes32(uint256(16)); // nextTokenId slot
        vm.store(address(ma), slot, bytes32(uint256(101)));
        assertEq(ma.getMintPrice(), (0.002 ether * 95) / 100);
    }

    function testGetMintPrice_FloorReached() public {
        // At some high supply, price should hit MIN_PRICE floor
        bytes32 slot = bytes32(uint256(16));
        vm.store(address(ma), slot, bytes32(uint256(5_001)));
        assertTrue(ma.getMintPrice() >= 0.0002 ether);

        // At max supply
        vm.store(address(ma), slot, bytes32(uint256(10_001)));
        assertEq(ma.getMintPrice(), 0.0002 ether);
    }

    // ============ Supply Exhaustion ============

    function testMintLastToken_Succeeds() public {
        bytes32 slot = bytes32(uint256(16));
        vm.store(address(ma), slot, bytes32(uint256(10_000))); // nextTokenId = 10_000 (= MAX_SUPPLY)

        vm.prevrandao(uint256(600));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        string memory solution = _solveChallenge(c);
        uint256 price = ma.getMintPrice();

        vm.prank(user, user);
        ma.mint{value: price}(solution);
        assertEq(ma.ownerOf(10_000), user);
    }

    // ============ NFT / ERC-721 Edge Cases ============

    function testTokenURIForNonexistentToken_Reverts() public {
        vm.expectRevert();
        ma.tokenURI(999);
    }

    function testTokenURIForTokenId0_Reverts() public {
        vm.expectRevert();
        ma.tokenURI(0);
    }

    function testTokenURIWithAgentCoinNotSet() public {
        MiningAgent ma2 = new MiningAgent();
        ma2.setLPVault(lpVault);
        // Don't set agentCoin

        vm.prevrandao(uint256(700));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma2.getChallenge(user);
        string memory solution = _solveChallenge(c);
        uint256 price = ma2.getMintPrice();

        vm.prank(user, user);
        ma2.mint{value: price}(solution);

        // Should return valid metadata with 0 mines/earnings
        string memory uri = ma2.tokenURI(1);
        assertTrue(_startsWith(uri, "data:application/json;base64,"));
    }

    function testSupportsInterface_ERC721() public view {
        // ERC-721 interface ID
        assertTrue(ma.supportsInterface(0x80ac58cd));
        // ERC-721 Enumerable
        assertTrue(ma.supportsInterface(0x780e9d63));
        // ERC-165
        assertTrue(ma.supportsInterface(0x01ffc9a7));
        // Random interface — false
        assertFalse(ma.supportsInterface(0xdeadbeef));
    }

    // ============ Reentrancy ============

    function testMint_ReentrancyViaMaliciousLPVault() public {
        ReentrantVault rv = new ReentrantVault(ma);
        MiningAgent ma2 = new MiningAgent();
        ma2.setLPVault(payable(address(rv)));
        ma2.setAgentCoin(address(mockAc));

        vm.prevrandao(uint256(800));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma2.getChallenge(user);
        string memory solution = _solveChallenge(c);

        // The reentrancy attempt in receive() targets ma (not ma2), and will fail
        // with "No contracts" (tx.origin != msg.sender). Reentrancy into ma2 is also
        // blocked by ReentrancyGuardTransient.
        vm.prank(user, user);
        ma2.mint{value: 0.002 ether}(solution);

        // Mint still succeeds
        assertEq(ma2.ownerOf(1), user);
    }

    // ============ Rarity Distribution ============

    function testRarity_AllTiersValid() public {
        // Mint several NFTs and verify all rarity values are in valid range [0,4]
        // and hashpower matches the tier
        for (uint256 i = 0; i < 10; ++i) {
            vm.prevrandao(uint256(keccak256(abi.encodePacked("rarity_test", i))));
            vm.prank(user, user);
            MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
            string memory solution = _solveChallenge(c);
            uint256 price = ma.getMintPrice();

            vm.prank(user, user);
            ma.mint{value: price}(solution);

            uint256 tokenId = ma.nextTokenId() - 1;
            uint8 r = ma.rarity(tokenId);
            uint16 hp = ma.hashpower(tokenId);

            assertTrue(r <= 4, "Rarity out of range");

            // Verify hashpower matches rarity tier
            if (r == 0) assertEq(hp, 100);
            else if (r == 1) assertEq(hp, 150);
            else if (r == 2) assertEq(hp, 200);
            else if (r == 3) assertEq(hp, 300);
            else assertEq(hp, 500);
        }
    }

    // ============ ERC-8004: Agent URI ============

    function testSetAgentURI_OwnerSucceeds() public {
        uint256 tokenId = _mintToken(user);
        vm.prank(user);
        ma.setAgentURI(tokenId, "https://agent.example.com/1.json");
        assertEq(ma.agentURI(tokenId), "https://agent.example.com/1.json");
    }

    function testSetAgentURI_Approved_Succeeds() public {
        uint256 tokenId = _mintToken(user);
        address approved = makeAddr("approved");
        vm.prank(user);
        ma.approve(approved, tokenId);

        vm.prank(approved);
        ma.setAgentURI(tokenId, "https://agent.example.com/approved.json");
        assertEq(ma.agentURI(tokenId), "https://agent.example.com/approved.json");
    }

    function testSetAgentURI_NonAuthorized_Reverts() public {
        uint256 tokenId = _mintToken(user);
        vm.prank(user2);
        vm.expectRevert("Not authorized");
        ma.setAgentURI(tokenId, "https://evil.com");
    }

    function testAgentURI_DefaultEmpty() public {
        uint256 tokenId = _mintToken(user);
        assertEq(ma.agentURI(tokenId), "");
    }

    function testAgentURI_NonexistentToken_Reverts() public {
        vm.expectRevert();
        ma.agentURI(999);
    }

    // ============ ERC-8004: Metadata ============

    function testSetMetadata_OwnerSucceeds() public {
        uint256 tokenId = _mintToken(user);
        vm.prank(user);
        ma.setMetadata(tokenId, "model", abi.encode("gpt-4"));
        assertEq(ma.getMetadata(tokenId, "model"), abi.encode("gpt-4"));
    }

    function testSetMetadata_ReservedKey_Reverts() public {
        uint256 tokenId = _mintToken(user);
        vm.prank(user);
        vm.expectRevert("Use setAgentWallet");
        ma.setMetadata(tokenId, "agentWallet", abi.encodePacked(user));
    }

    function testSetMetadata_NonAuthorized_Reverts() public {
        uint256 tokenId = _mintToken(user);
        vm.prank(user2);
        vm.expectRevert("Not authorized");
        ma.setMetadata(tokenId, "model", abi.encode("evil"));
    }

    function testGetMetadata_ReturnsSetValue() public {
        uint256 tokenId = _mintToken(user);
        vm.prank(user);
        ma.setMetadata(tokenId, "capabilities", hex"deadbeef");
        assertEq(ma.getMetadata(tokenId, "capabilities"), hex"deadbeef");
    }

    function testGetMetadata_NonexistentToken_Reverts() public {
        vm.expectRevert();
        ma.getMetadata(999, "model");
    }

    // ============ ERC-8004: Agent Wallet ============

    function testSetAgentWallet_ValidSignature() public {
        uint256 tokenId = _mintToken(user);
        (address wallet, uint256 walletPk) = makeAddrAndKey("agentWallet");
        uint256 deadline = block.timestamp + 60;

        bytes memory sig = _signAgentWallet(walletPk, tokenId, wallet, user, deadline);

        vm.prank(user);
        ma.setAgentWallet(tokenId, wallet, deadline, sig);
        assertEq(ma.getAgentWallet(tokenId), wallet);
    }

    function testSetAgentWallet_InvalidSignature_Reverts() public {
        uint256 tokenId = _mintToken(user);
        (address wallet,) = makeAddrAndKey("agentWallet");
        (, uint256 wrongPk) = makeAddrAndKey("wrongKey");
        uint256 deadline = block.timestamp + 60;

        bytes memory sig = _signAgentWallet(wrongPk, tokenId, wallet, user, deadline);

        vm.prank(user);
        vm.expectRevert("Invalid signature");
        ma.setAgentWallet(tokenId, wallet, deadline, sig);
    }

    function testSetAgentWallet_DeadlineExpired_Reverts() public {
        uint256 tokenId = _mintToken(user);
        (address wallet, uint256 walletPk) = makeAddrAndKey("agentWallet");
        uint256 deadline = block.timestamp - 1;

        bytes memory sig = _signAgentWallet(walletPk, tokenId, wallet, user, deadline);

        vm.prank(user);
        vm.expectRevert("Deadline expired");
        ma.setAgentWallet(tokenId, wallet, deadline, sig);
    }

    function testSetAgentWallet_DeadlineTooFar_Reverts() public {
        uint256 tokenId = _mintToken(user);
        (address wallet, uint256 walletPk) = makeAddrAndKey("agentWallet");
        uint256 deadline = block.timestamp + 6 minutes;

        bytes memory sig = _signAgentWallet(walletPk, tokenId, wallet, user, deadline);

        vm.prank(user);
        vm.expectRevert("Deadline too far");
        ma.setAgentWallet(tokenId, wallet, deadline, sig);
    }

    function testSetAgentWallet_ZeroAddress_Reverts() public {
        uint256 tokenId = _mintToken(user);
        uint256 deadline = block.timestamp + 60;

        vm.prank(user);
        vm.expectRevert("Invalid wallet");
        ma.setAgentWallet(tokenId, address(0), deadline, "");
    }

    function testGetAgentWallet_ReturnsAddress() public {
        uint256 tokenId = _mintToken(user);
        // After mint, agentWallet is auto-set to msg.sender
        assertEq(ma.getAgentWallet(tokenId), user);
    }

    function testUnsetAgentWallet_OwnerSucceeds() public {
        uint256 tokenId = _mintToken(user);
        assertEq(ma.getAgentWallet(tokenId), user);

        vm.prank(user);
        ma.unsetAgentWallet(tokenId);
        assertEq(ma.getAgentWallet(tokenId), address(0));
    }

    // ============ ERC-8004: Transfer Clears Wallet ============

    function testTransfer_ClearsAgentWallet() public {
        uint256 tokenId = _mintToken(user);
        assertEq(ma.getAgentWallet(tokenId), user);

        vm.prank(user);
        ma.transferFrom(user, user2, tokenId);
        assertEq(ma.getAgentWallet(tokenId), address(0));
    }

    function testTransfer_MetadataPreserved() public {
        uint256 tokenId = _mintToken(user);
        vm.prank(user);
        ma.setMetadata(tokenId, "model", abi.encode("claude"));

        vm.prank(user);
        ma.transferFrom(user, user2, tokenId);

        // Non-wallet metadata survives transfer
        assertEq(ma.getMetadata(tokenId, "model"), abi.encode("claude"));
        // But wallet is cleared
        assertEq(ma.getAgentWallet(tokenId), address(0));
    }

    // ============ ERC-8004: Registration ============

    function testMint_EmitsRegisteredEvent() public {
        vm.prevrandao(uint256(900));
        vm.prank(user, user);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(user);
        string memory solution = _solveChallenge(c);
        uint256 price = ma.getMintPrice();

        vm.prank(user, user);
        vm.expectEmit(true, false, true, true);
        emit MiningAgent.Registered(1, "", user);
        ma.mint{value: price}(solution);
    }

    function testMint_SetsDefaultAgentWallet() public {
        uint256 tokenId = _mintToken(user);
        assertEq(ma.getAgentWallet(tokenId), user);
    }

    // ============ ERC-8004: Utility ============

    function testIsAuthorizedOrOwner_Owner_True() public {
        uint256 tokenId = _mintToken(user);
        assertTrue(ma.isAuthorizedOrOwner(user, tokenId));
    }

    function testIsAuthorizedOrOwner_Approved_True() public {
        uint256 tokenId = _mintToken(user);
        address approved = makeAddr("approved");
        vm.prank(user);
        ma.approve(approved, tokenId);
        assertTrue(ma.isAuthorizedOrOwner(approved, tokenId));
    }

    function testIsAuthorizedOrOwner_Random_False() public {
        uint256 tokenId = _mintToken(user);
        assertFalse(ma.isAuthorizedOrOwner(user2, tokenId));
    }

    // ============ Helpers ============

    function _mintToken(address minter) internal returns (uint256) {
        uint256 tokenId = ma.nextTokenId();
        vm.prevrandao(uint256(keccak256(abi.encodePacked("mint", tokenId))));
        vm.prank(minter, minter);
        MiningAgent.SMHLChallenge memory c = ma.getChallenge(minter);
        string memory solution = _solveChallenge(c);
        uint256 price = ma.getMintPrice();
        vm.prank(minter, minter);
        ma.mint{value: price}(solution);
        return tokenId;
    }

    function _signAgentWallet(uint256 pk, uint256 agentId, address newWallet, address owner, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 TYPEHASH = keccak256("AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, agentId, newWallet, owner, deadline));

        // Compute EIP-712 domain separator matching MiningAgent's EIP712("MiningAgent", "1")
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("MiningAgent"),
                keccak256("1"),
                block.chainid,
                address(ma)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _solveChallenge(MiningAgent.SMHLChallenge memory challenge) internal pure returns (string memory) {
        bytes memory solution = new bytes(challenge.totalLength);
        bool[] memory isSpace = new bool[](challenge.totalLength);

        for (uint256 i = 0; i < challenge.totalLength; ++i) {
            solution[i] = bytes1(uint8(65));
        }

        uint256 spacesNeeded = challenge.wordCount - 1;
        uint256 cursor = challenge.totalLength - 2;
        for (uint256 i = 0; i < spacesNeeded; ++i) {
            while (
                cursor < challenge.firstNChars || cursor == challenge.charPosition || isSpace[cursor]
                    || (cursor > 0 && isSpace[cursor - 1])
                    || (cursor + 1 < challenge.totalLength && isSpace[cursor + 1])
            ) {
                unchecked { --cursor; }
            }
            solution[cursor] = bytes1(uint8(32));
            isSpace[cursor] = true;
            if (cursor > 1) cursor -= 2;
        }

        uint256 currentSum;
        for (uint256 i = 0; i < challenge.firstNChars; ++i) {
            if (i == challenge.charPosition) {
                solution[i] = bytes1(challenge.charValue);
            } else {
                solution[i] = bytes1(uint8(33));
            }
            currentSum += uint8(solution[i]);
        }

        uint256 remaining = challenge.targetAsciiSum - currentSum;
        for (uint256 i = 0; i < challenge.firstNChars && remaining > 0; ++i) {
            if (i == challenge.charPosition) continue;
            uint256 add = remaining > 93 ? 93 : remaining;
            solution[i] = bytes1(uint8(solution[i]) + uint8(add));
            remaining -= add;
        }

        require(remaining == 0, "Unsolvable challenge");

        if (challenge.charPosition >= challenge.firstNChars) {
            solution[challenge.charPosition] = bytes1(challenge.charValue);
        }

        return string(solution);
    }

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
