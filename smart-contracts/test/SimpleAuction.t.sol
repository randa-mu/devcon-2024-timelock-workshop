// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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
        bidder1 = address(1);
        bidder2 = address(2);

        auction = new SimpleAuction(
            durationBlocks,
            reservePrice,
            highestBidPaymentWindowBlocks
        );
    }

    function test_DeploymentConfigurations() public view {
        assertEq(auction.auctioneer(), address(this));
    }


}
