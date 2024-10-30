// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";

import {SimpleAuction} from "../../src/SimpleAuction.sol";
import {SimpleAuction} from "../../src/SimpleAuction.sol";
import {SignatureSchemeAddressProvider} from "../../src/signature-schemes/SignatureSchemeAddressProvider.sol";
import {SignatureSender} from "../../src/signature-requests/SignatureSender.sol";
import {BlocklockSender} from "../../src/blocklock/BlocklockSender.sol";
import {BlocklockSignatureScheme} from "../../src/blocklock/BlocklockSignatureScheme.sol";
import {BLS} from "../../src/lib/BLS.sol";

contract SimpleAuctionTest is Test {
    SimpleAuction public auction;
    SignatureSender public sigSender;

    uint256 public durationBlocks = 10;
    uint256 public reservePrice = 0.1 ether;
    uint256 public highestBidPaymentWindowBlocks = 5;

    string public SCHEME_ID = "BN254-BLS-BLOCKLOCK";

    bytes public validPK =
        hex"1f0f94e91134493239ebfd2f04512f3373cd3428e053781aa9042b17a343153121be6292ba21684615dd4d19b8d16f33e3c626cf6954ed1ba84651eba38d98ca2a4957873ebe242e373087ad3f0ccf72bec5170cde129c214a159bbaf9947dc916480fa950be8d8aa3b446b817b9a25f3691429f6d93ab5d0bbc1cadf9f63dc3";

    address auctioneer;
    address bidder1;
    address bidder2;

    function setUp() public {
        auctioneer = vm.addr(1); // Use the test contract as auctioneer
        bidder1 = vm.addr(2);
        bidder2 = vm.addr(3);

        vm.startPrank(auctioneer);

        SignatureSchemeAddressProvider sigAddrProvider = new SignatureSchemeAddressProvider();
        BlocklockSignatureScheme tlockScheme = new BlocklockSignatureScheme();
        sigAddrProvider.updateSignatureScheme(SCHEME_ID, address(tlockScheme));

        BLS.PointG2 memory pk = abi.decode(validPK, (BLS.PointG2));
        sigSender = new SignatureSender(pk.x, pk.y, address(sigAddrProvider));

        BlocklockSender tlock = new BlocklockSender(address(sigSender));
        auction = new SimpleAuction(durationBlocks, reservePrice, highestBidPaymentWindowBlocks, address(tlock));

        vm.stopPrank();
    }

    function test_DeploymentConfigurations() public view {
        assertEq(auction.auctioneer(), auctioneer);
        assertGt(auction.auctionEndBlock(), block.number);
        assertEq(auction.highestBidPaymentDeadlineBlock(), auction.auctionEndBlock() + highestBidPaymentWindowBlocks);
    }

    function test_BidPlacement() public {
        // Simulate bidding
        uint256 bidAmount = 1000;
        vm.deal(bidder1, 1 ether); // Give bidder1 1 ether
        vm.prank(bidder1);
        auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount)); // Place a sealed bid of bidAmount

        assertEq(auction.totalBids(), 1, "Bid count should be 1");
    }

    function test_RevealBid() public {
        // First, place a bid
        uint256 bidAmount = 0.5 ether;
        vm.deal(bidder1, 1 ether);
        vm.startPrank(bidder1);
        uint256 bidID = auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount)); // Place a sealed bid of bidAmount
        vm.stopPrank();

        // Move to the auction end block to end the auction
        vm.roll(auction.auctionEndBlock() + 1);

        // Receive the decryption key for the bid id from the timelock contract
        vm.startPrank(auctioneer);
        bytes memory validSignature =
            hex"140bec1c035d7a6d407c4a823faeea31de69769db8db9c86aaf7a9682daa23bb2fd2f8ecfe15552b488ba3fd075eff3f9739c44b299b8d0851c9e93e740925ab";
        sigSender.fulfilSignatureRequest(bidID, validSignature);
        vm.stopPrank();

        // Reveal the bid
        auction.revealBid(bidID, bidAmount); // Reveal the bid

        SimpleAuction.Bid memory b = auction.getBidWithBidID(bidID);

        assertEq(auction.highestBidder(), bidder1, "Highest bidder should be bidder1");
        assertEq(b.bidder, bidder1, "Bidder for bid ID 1 should be bidder1");
        assertEq(auction.highestBid(), bidAmount, "Highest bid should be 1000");
    }

    function test_FulfillHighestBid() public {
        // Bidder1 places a bid
        uint256 bidAmount = 0.5 ether;
        vm.deal(bidder1, 1 ether);
        vm.startPrank(bidder1);
        uint256 bidID = auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount)); // Place a sealed bid of bidAmount
        vm.stopPrank();

        // Move to the auction end block to end the auction
        vm.roll(auction.auctionEndBlock() + 1);

        // Receive the decryption key for the bid id from the timelock contract
        vm.startPrank(auctioneer);
        bytes memory validSignature =
            hex"140bec1c035d7a6d407c4a823faeea31de69769db8db9c86aaf7a9682daa23bb2fd2f8ecfe15552b488ba3fd075eff3f9739c44b299b8d0851c9e93e740925ab";
        sigSender.fulfilSignatureRequest(bidID, validSignature);
        vm.stopPrank();

        // Reveal the bid
        auction.revealBid(bidID, bidAmount); // Reveal the bid

        // Bidder1 fulfills the highest bid
        vm.startPrank(bidder1); // Set bidder1 as the sender
        auction.fulfilHighestBid{value: bidAmount - auction.reservePrice()}();
        vm.stopPrank();

        assert(auction.highestBidPaid());
    }

    function test_WithdrawDeposit() public {
        // Bidder1 places a bid
        uint256 bidAmount = 0.5 ether;
        vm.deal(bidder1, 1 ether);
        vm.startPrank(bidder1);
        uint256 bidID = auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount)); // Place a sealed bid of bidAmount
        vm.stopPrank();

        // Bidder2 places a bid
        uint256 bidAmount2 = 0.1 ether;
        vm.deal(bidder2, 1 ether);
        vm.startPrank(bidder2);
        uint256 bidID2 = auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount2)); // Place a sealed bid of bidAmount
        vm.stopPrank();

        // Move to the auction end block to end the auction
        vm.roll(auction.auctionEndBlock() + 1);

        // Receive the decryption key for the bid ids from the timelock contract
        vm.startPrank(auctioneer);
        bytes memory validSignature =
            hex"140bec1c035d7a6d407c4a823faeea31de69769db8db9c86aaf7a9682daa23bb2fd2f8ecfe15552b488ba3fd075eff3f9739c44b299b8d0851c9e93e740925ab";
        sigSender.fulfilSignatureRequest(1, validSignature);

        // Reveal the bid
        auction.revealBid(bidID, bidAmount); // Reveal the bid
        auction.revealBid(bidID2, bidAmount2);

        // Bidder1 cannot withdraw their deposit
        vm.startPrank(bidder1); // Set bidder1 as the sender
        vm.expectRevert("Highest bidder cannot claim the reserve.");
        auction.withdrawDeposit();
        vm.stopPrank();

        // Bidder2 can withdraw their deposit
        vm.startPrank(bidder2); // Set bidder1 as the sender
        auction.withdrawDeposit();
        vm.stopPrank();
    }

    function test_WithdrawForfeitedDeposit() public {
        // Bidder1 places a bid
        uint256 bidAmount = 0.5 ether;
        vm.deal(bidder1, 1 ether);
        vm.startPrank(bidder1);
        uint256 bidID = auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount)); // Place a sealed bid of bidAmount
        vm.stopPrank();

        // Move to the auction end block to end the auction
        vm.roll(auction.auctionEndBlock() + 1);

        // Receive the decryption key for the bid id from the timelock contract
        vm.startPrank(auctioneer);
        bytes memory validSignature =
            hex"140bec1c035d7a6d407c4a823faeea31de69769db8db9c86aaf7a9682daa23bb2fd2f8ecfe15552b488ba3fd075eff3f9739c44b299b8d0851c9e93e740925ab";
        sigSender.fulfilSignatureRequest(bidID, validSignature);
        vm.stopPrank();

        // Reveal the bid
        auction.revealBid(bidID, bidAmount); // Reveal the bid

        // Bidder1 fails to fulfill the highest bid payment within payment window
        vm.roll(block.number + highestBidPaymentWindowBlocks + 1); // Move past payment deadline

        // Auctioneer tries to withdraw the forfeited deposit
        vm.startPrank(auctioneer); // Set auctioneer as the sender
        auction.withdrawForfeitedDepositFromHighestBidder();
        vm.stopPrank();
    }
}
