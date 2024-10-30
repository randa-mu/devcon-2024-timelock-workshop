// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SimpleAuction} from "../src/SimpleAuction.sol";

contract SimpleAuctionScript is Script {
    SimpleAuction public simpleAuction;
    uint256 public durationBlocks = 10;
    uint256 public reservePrice = 0.1 ether;
    uint256 public highestBidPaymentWindowBlocks = 5;

    function run() public {
        vm.startBroadcast();

        // simpleAuction = new SimpleAuction(durationBlocks, reservePrice, highestBidPaymentWindowBlocks);

        // console.log("Simple Auction contract deployed to:", address(simpleAuction));
        // console.log("Auction duration in blocks:", durationBlocks);
        // console.log("Auction end block number:", block.number + durationBlocks + highestBidPaymentWindowBlocks);
        // console.log("Auction reserve price in wei:", reservePrice);
        // console.log("Window for fulfilling highest bid in blocks post-auction:", highestBidPaymentWindowBlocks);

        vm.stopBroadcast();
    }
}
