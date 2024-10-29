// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SimpleAuction} from "../src/SimpleAuction.sol";

contract SimpleAuctionScript is Script {
    SimpleAuction public simpleAuction;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        simpleAuction = new SimpleAuction();
        console.log("Simple Auction contract deployed to:", address(simpleAuction));
        // todo log constructor parameters as well

        vm.stopBroadcast();
    }
}
