// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {SimpleAuction} from "../../src/SimpleAuction.sol";
import {SignatureSchemeAddressProvider} from "../../src/signature-schemes/SignatureSchemeAddressProvider.sol";
import {SignatureSender} from "../../src/signature-requests/SignatureSender.sol";
import {BlocklockSender} from "../../src/blocklock/BlocklockSender.sol";
import {BlocklockSignatureScheme} from "../../src/blocklock/BlocklockSignatureScheme.sol";
import {DecryptionSender} from "../../src/decryption-requests/DecryptionSender.sol";
import {BLS} from "../../src/lib/BLS.sol";
import {TypesLib} from "../../src/lib/TypesLib.sol";

contract SimpleAuctionTest is Test {
    SimpleAuction public auction;
    SignatureSender public sigSender;
    DecryptionSender public decryptionSender;
    BlocklockSender public tlock;

    string SCHEME_ID = "BN254-BLS-BLOCKLOCK";

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public durationBlocks = 12;
    uint256 public reservePrice = 0.1 ether;
    uint256 public highestBidPaymentWindowBlocks = 5;

    address owner;
    address auctioneer;
    address bidder1;
    address bidder2;

    // todo try bytes input for ciphertext and run tests again

    // create ciphertexts for bid amounts
    // e.g., bid amount - 3 ether - 3000000000000000000 wei
    // block number - durationBlocks + 1 = 11
    // yarn timelock:encrypt --message 3000000000000000000 --blocknumber 11
    // 3 ether for bidder 1 and 4 ether for bidder 2
    TypesLib.Ciphertext sealedBidBidder1 = TypesLib.Ciphertext({
        u: BLS.PointG2({
            x: [
                14142380308423906610328325205633754694002301558654408701934220147059967542660,
                4795984740938726483924720262587026838890051381570343702421443260575124596446
            ],
            y: [
                13301122453285478420056122708237526083484415709254283392885579853639158169617,
                11125759247493978573666410429063118092803139083876927879642973106997490249635
            ]
        }),
        v: hex"63f745f4240f4708db37b0fa0e40309a37ab1a65f9b1be4ac716a347d4fe57fe",
        w: hex"e8aadd66a9a67c00f134b1127b7ef85046308c340f2bb7cee431bd7bfe950bd4"
    });

    // todo create signatures or decryption keys for both bids for block number 11

    function setUp() public {
        auctioneer = vm.addr(1);
        owner = auctioneer;
        bidder1 = vm.addr(2);
        bidder2 = vm.addr(3);

        vm.startPrank(auctioneer);

        SignatureSchemeAddressProvider sigAddrProvider = new SignatureSchemeAddressProvider(owner);
        BlocklockSignatureScheme tlockScheme = new BlocklockSignatureScheme();
        sigAddrProvider.updateSignatureScheme(SCHEME_ID, address(tlockScheme));

        BLS.PointG2 memory pk = BLS.PointG2({
            x: [
                17445541620214498517833872661220947475697073327136585274784354247720096233162,
                18268991875563357240413244408004758684187086817233527689475815128036446189503
            ],
            y: [
                11401601170172090472795479479864222172123705188644469125048759621824127399516,
                8044854403167346152897273335539146380878155193886184396711544300199836788154
            ]
        });
        sigSender = new SignatureSender(pk.x, pk.y, owner, address(sigAddrProvider));

        decryptionSender = new DecryptionSender(pk.x, pk.y, owner, address(sigAddrProvider));

        tlock = new BlocklockSender(address(decryptionSender));
        auction = new SimpleAuction(durationBlocks, reservePrice, highestBidPaymentWindowBlocks, address(tlock));

        vm.stopPrank();
    }

    function test_DeploymentConfigurations() public view {
        assertEq(auction.auctioneer(), auctioneer);
        assertGt(auction.auctionEndBlock(), block.number);
        assertEq(auction.highestBidPaymentDeadlineBlock(), auction.auctionEndBlock() + highestBidPaymentWindowBlocks);
        assertTrue(decryptionSender.hasRole(ADMIN_ROLE, auctioneer));
    }

    function test_BidPlacement() public {
        // Simulate bidding
        vm.deal(bidder1, 1 ether); // Give bidder1 1 ether for reserve price payment requirement
        vm.startPrank(bidder1);
        auction.sealedBid{value: auction.reservePrice()}(sealedBidBidder1); // Place a sealed bid of 3 ether in wei
        assertEq(auction.totalBids(), 1, "Bid count should be 1");
        vm.stopPrank();
    }

    function testFail_BidReplacement() public {
        // Simulate bidding
        vm.deal(bidder1, 1 ether);
        vm.startPrank(bidder1);
        auction.sealedBid{value: auction.reservePrice()}(sealedBidBidder1);
        assertEq(auction.totalBids(), 1, "Bid count should be 1");
        // Bids cannot be overwritten
        auction.sealedBid{value: auction.reservePrice()}(sealedBidBidder1);
        vm.stopPrank();
    }

    function test_RevealBid() public {
        uint256 bidAmount = 3 ether;
        console.log(bidAmount);

        // First, place a bid
        vm.deal(bidder1, 1 ether);
        vm.startPrank(bidder1);
        uint256 bidID = auction.sealedBid{value: auction.reservePrice()}(sealedBidBidder1);
        vm.stopPrank();

        // Move to the auction end block to end the auction
        vm.roll(auction.auctionEndBlock() + 1);

        // Receive the decryption key for the bid id from the timelock contract
        // This should also decrypt the sealed bid
        vm.startPrank(auctioneer);
        bytes memory signature =
            hex"02b3b2fa2c402d59e22a2f141e32a092603862a06a695cbfb574c440372a72cd0636ba8092f304e7701ae9abe910cb474edf0408d9dd78ea7f6f97b7f2464711";
        bytes memory decryptionKey = hex"7ec49d8f06b34d8d6b2e060ea41652f25b1325fafb041bba9cf24f094fbca259";
        decryptionSender.fulfilDecryptionRequest(bidID, decryptionKey, signature);

        auction.revealBid(1);
        vm.stopPrank();

        (,,, address bidderAddressWithBidID,) = auction.getBidWithBidID(bidID);
        (,,, address bidderAddressWithBidder,) = auction.getBidWithBidder(bidder1);

        assertEq(auction.highestBidder(), bidder1, "Highest bidder should be bidder1");
        assertEq(bidderAddressWithBidID, bidder1, "Bidder for bid ID 1 should be bidder1");
        assertEq(bidderAddressWithBidder, bidder1, "Bidder for bid ID 1 should be bidder 1");
        assertEq(auction.highestBid(), bidAmount, "Highest bid should be bid amount");
    }

    // function test_FulfillHighestBid() public {
    //     // Bidder1 places a bid
    //     uint256 bidAmount = 0.5 ether;
    //     vm.deal(bidder1, 1 ether);
    //     vm.startPrank(bidder1);
    //     uint256 bidID = auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount)); // Place a sealed bid of bidAmount
    //     vm.stopPrank();

    //     // Move to the auction end block to end the auction
    //     vm.roll(auction.auctionEndBlock() + 1);

    //     // Receive the decryption key for the bid id from the timelock contract
    //     vm.startPrank(auctioneer);
    //     bytes memory validSignature =
    //         hex"140bec1c035d7a6d407c4a823faeea31de69769db8db9c86aaf7a9682daa23bb2fd2f8ecfe15552b488ba3fd075eff3f9739c44b299b8d0851c9e93e740925ab";
    //     sigSender.fulfilSignatureRequest(bidID, validSignature);

    //     // Reveal the bid
    //     auction.revealBid(bidID, bidAmount); // Reveal the bid
    //     vm.stopPrank();

    //     // Bidder1 fulfills the highest bid
    //     vm.startPrank(bidder1); // Set bidder1 as the sender
    //     auction.fulfilHighestBid{value: bidAmount - auction.reservePrice()}();
    //     vm.stopPrank();

    //     assert(auction.highestBidPaid());
    // }

    // function test_WithdrawDeposit() public {
    //     // Bidder1 places a bid
    //     uint256 bidAmount = 0.5 ether;
    //     vm.deal(bidder1, 1 ether);
    //     vm.startPrank(bidder1);
    //     uint256 bidID = auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount)); // Place a sealed bid of bidAmount
    //     vm.stopPrank();

    //     // Bidder2 places a bid
    //     uint256 bidAmount2 = 0.1 ether;
    //     vm.deal(bidder2, 1 ether);
    //     vm.startPrank(bidder2);
    //     uint256 bidID2 = auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount2)); // Place a sealed bid of bidAmount
    //     vm.stopPrank();

    //     // Move to the auction end block to end the auction
    //     vm.roll(auction.auctionEndBlock() + 1);

    //     // Receive the decryption key for the bid ids from the timelock contract
    //     vm.startPrank(auctioneer);
    //     bytes memory validSignature =
    //         hex"140bec1c035d7a6d407c4a823faeea31de69769db8db9c86aaf7a9682daa23bb2fd2f8ecfe15552b488ba3fd075eff3f9739c44b299b8d0851c9e93e740925ab";
    //     sigSender.fulfilSignatureRequest(1, validSignature);

    //     // Reveal the bid
    //     auction.revealBid(bidID, bidAmount); // Reveal the bid
    //     auction.revealBid(bidID2, bidAmount2);

    //     vm.stopPrank();

    //     // Bidder1 cannot withdraw their deposit
    //     vm.startPrank(bidder1); // Set bidder1 as the sender
    //     vm.expectRevert("Highest bidder cannot claim the reserve.");
    //     auction.withdrawDeposit();
    //     vm.stopPrank();

    //     // Bidder2 can withdraw their deposit
    //     vm.startPrank(bidder2); // Set bidder1 as the sender
    //     auction.withdrawDeposit();
    //     vm.stopPrank();
    // }

    // function test_WithdrawForfeitedDeposit() public {
    //     // Bidder1 places a bid
    //     uint256 bidAmount = 0.5 ether;
    //     vm.deal(bidder1, 1 ether);
    //     vm.startPrank(bidder1);
    //     uint256 bidID = auction.sealedBid{value: auction.reservePrice()}(abi.encodePacked(bidAmount)); // Place a sealed bid of bidAmount
    //     vm.stopPrank();

    //     // Move to the auction end block to end the auction
    //     vm.roll(auction.auctionEndBlock() + 1);

    //     // Receive the decryption key for the bid id from the timelock contract
    //     vm.startPrank(auctioneer);
    //     bytes memory validSignature =
    //         hex"140bec1c035d7a6d407c4a823faeea31de69769db8db9c86aaf7a9682daa23bb2fd2f8ecfe15552b488ba3fd075eff3f9739c44b299b8d0851c9e93e740925ab";
    //     sigSender.fulfilSignatureRequest(bidID, validSignature);

    //     // Reveal the bid
    //     auction.revealBid(bidID, bidAmount); // Reveal the bid
    //     vm.stopPrank();

    //     // Bidder1 fails to fulfill the highest bid payment within payment window
    //     vm.roll(block.number + highestBidPaymentWindowBlocks + 1); // Move past payment deadline

    //     // Auctioneer tries to withdraw the forfeited deposit
    //     vm.startPrank(auctioneer); // Set auctioneer as the sender
    //     auction.withdrawForfeitedDepositFromHighestBidder();
    //     vm.stopPrank();
    // }
}
