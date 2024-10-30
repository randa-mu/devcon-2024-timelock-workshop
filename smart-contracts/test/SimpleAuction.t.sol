// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAuction} from "../src/SimpleAuction.sol";

contract SimpleAuctionTest is Test {
    SimpleAuction public auction;
    uint256 public durationBlocks = 10;
    uint256 public reservePrice = 0.1 ether;
    uint256 public highestBidPaymentWindowBlocks = 5;

    address auctioneer;
    address bidder1;
    address bidder2;

    function setUp() public {
        auctioneer = vm.addr(1); // Use the test contract as auctioneer
        bidder1 = vm.addr(2);
        bidder2 = vm.addr(3);

        vm.startPrank(auctioneer);
        auction = new SimpleAuction(durationBlocks, reservePrice, highestBidPaymentWindowBlocks);
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
        // todo only .prank(addr) not working for some reason??
        // vm.prank(bidder1);
        uint256 bidID = auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount)); // Place a sealed bid of bidAmount
        vm.stopPrank();

        // Move to the auction end block to end the auction
        vm.roll(auction.auctionEndBlock() + 1);

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
        // todo only .prank(addr) not working for some reason??
        // vm.prank(bidder1);
        uint256 bidID = auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount)); // Place a sealed bid of bidAmount
        vm.stopPrank();

        // Move to the auction end block to end the auction
        vm.roll(auction.auctionEndBlock() + 1);

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
        // todo only .prank(addr) not working for some reason??
        // vm.prank(bidder1);
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
        // todo only .prank(addr) not working for some reason??
        // vm.prank(bidder1);
        uint256 bidID = auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount)); // Place a sealed bid of bidAmount
        vm.stopPrank();

        // Move to the auction end block to end the auction
        vm.roll(auction.auctionEndBlock() + 1);

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
