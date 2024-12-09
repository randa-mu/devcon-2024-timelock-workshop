// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {SimpleAuction} from "../src/SimpleAuction.sol";
import {SignatureSchemeAddressProvider} from "../src/signature-schemes/SignatureSchemeAddressProvider.sol";
import {SignatureSender} from "../src/signature-requests/SignatureSender.sol";
import {BlocklockSender} from "../src/blocklock/BlocklockSender.sol";
import {BlocklockSignatureScheme} from "../src/blocklock/BlocklockSignatureScheme.sol";
import {BLS} from "../src/lib/BLS.sol";

contract SimpleAuctionScript is Script {
    uint256 public durationBlocks = 10;
    uint256 public reservePrice = 0.1 ether;
    uint256 public highestBidPaymentWindowBlocks = 5;
    string public SCHEME_ID = "BN254-BLS-BLOCKLOCK";

    function run() public {
        vm.startBroadcast();

        address owner = msg.sender;
        
        // Deploy signature scheme address provider
        SignatureSchemeAddressProvider sigAddrProvider = new SignatureSchemeAddressProvider(owner);
        console.log("SignatureSchemeAddressProvider deployed to:", address(sigAddrProvider));

        // Deploy blocklock signature scheme
        BlocklockSignatureScheme tlockScheme = new BlocklockSignatureScheme();
        console.log("BlocklockSignatureScheme deployed to:", address(tlockScheme));

        // Register signature scheme in scheme address provider
        sigAddrProvider.updateSignatureScheme(SCHEME_ID, address(tlockScheme));

        // Deploy Signature Sender
        bytes memory validPK =
            hex"1053ca090929d58ca117e0295d110bb76a0d80963cbf31d55046631cf7bc74d6169229de700b59ec8fdaa0333664cb05c22b3a365544275696f94afd47108487048833a4b3115b9e6b09f679b620862dfd9c6fb1a7e2d6e1cfff2d463f6901e713209084ce174365fe42524f7cb19934106c3f6a347a74faf25ebd51bdef1160";
        BLS.PointG2 memory pk = abi.decode(validPK, (BLS.PointG2));

        SignatureSender sigsender = new SignatureSender(pk.x, pk.y, owner, address(sigAddrProvider));
        console.log("SignatureSender deployed to:", address(sigsender));

        BlocklockSender tlock = new BlocklockSender(address(sigsender));
        console.log("BlocklockSender deployed to:", address(tlock));

        // Deploy simple auction
        SimpleAuction simpleAuction =
            new SimpleAuction(durationBlocks, reservePrice, highestBidPaymentWindowBlocks, address(tlock));

        console.log("\nSimpleAuction configuration parameters");
        console.log("Simple Auction contract deployed to:", address(simpleAuction));
        console.log("Auction duration in blocks:", durationBlocks);
        console.log("Auction end block number:", block.number + durationBlocks + highestBidPaymentWindowBlocks);
        console.log("Auction reserve price in wei:", reservePrice);
        console.log("Window for fulfilling highest bid in blocks post-auction:", highestBidPaymentWindowBlocks);

        vm.stopBroadcast();
    }
}
