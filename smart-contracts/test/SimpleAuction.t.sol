// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {SimpleAuction} from "../src/SimpleAuction.sol";

contract SimpleAuctionTest is Test {
    SimpleAuction public auction;

    function setUp() public {
        auction = new SimpleAuction();
    }

    // function test_DeploymentConfigurations() public view {
    //     assertNotEq(auction.auctioneer(), address(0));
    // }
}
