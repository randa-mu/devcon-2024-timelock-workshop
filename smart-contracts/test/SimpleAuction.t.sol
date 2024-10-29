// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAuction} from "../src/SimpleAuction.sol";

contract SimpleAuctionTest is Test {
    SimpleAuction public auction;
    uint256 public durationBlocks = 10;
    uint256 public reservePrice = 0.1 ether;
    uint256 public highestBidPaymentWindowBlocks = 5;

    function setUp() public {
        auction = new SimpleAuction(
            durationBlocks,
            reservePrice,
            highestBidPaymentWindowBlocks
        );
    }

    // function test_DeploymentConfigurations() public view {
    //     assertNotEq(auction.auctioneer(), address(0));
    // }
}
