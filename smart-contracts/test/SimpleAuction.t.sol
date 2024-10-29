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
        auctioneer = address(this); // Use the test contract as auctioneer

        bidder1 = vm.addr(1);
        bidder2 = vm.addr(2);

        auction = new SimpleAuction(durationBlocks, reservePrice, highestBidPaymentWindowBlocks);
    }

    function test_DeploymentConfigurations() public view {
        assertEq(auction.auctioneer(), address(this));
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
}
