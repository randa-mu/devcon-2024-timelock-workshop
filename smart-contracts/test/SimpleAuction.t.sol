// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAuction} from "../src/SimpleAuction.sol";

contract SimpleAuctionTest is Test {
    SimpleAuction public auction;
    uint256 public constant durationMinutes = 1;
    uint256 public constant reservePrice = 1;
    uint256 public constant paymentWindowMinutes = 1;

    function setUp() public {
        auction = new SimpleAuction(durationMinutes, reservePrice, paymentWindowMinutes);
    }

    function test_DeploymentConfigurations() public view {
        assertNotEq(auction.auctioneer(), address(0));
    }
}
