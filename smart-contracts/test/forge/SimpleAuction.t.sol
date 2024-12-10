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

    // create ciphertexts for bid amounts
    // bidder1
    // e.g., bid amount - 3 ether - 3000000000000000000 wei
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
    bytes signatureBidder1 =
        hex"02b3b2fa2c402d59e22a2f141e32a092603862a06a695cbfb574c440372a72cd0636ba8092f304e7701ae9abe910cb474edf0408d9dd78ea7f6f97b7f2464711";
    bytes decryptionKeyBidder1 = hex"7ec49d8f06b34d8d6b2e060ea41652f25b1325fafb041bba9cf24f094fbca259";

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
        auction = new SimpleAuction(owner, durationBlocks, reservePrice, highestBidPaymentWindowBlocks, address(tlock));

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

        decryptionSender.fulfilDecryptionRequest(bidID, decryptionKeyBidder1, signatureBidder1);

        auction.revealBid(bidID);
        vm.stopPrank();

        (,, uint256 unsealedAmount, address bidderAddressWithBidID,) = auction.getBidWithBidID(bidID);
        (,,, address bidderAddressWithBidder,) = auction.getBidWithBidder(bidder1);

        assertEq(auction.highestBidder(), bidder1, "Highest bidder should be bidder1");
        assertEq(bidderAddressWithBidID, bidder1, "Bidder for bid ID 1 should be bidder1");
        assertEq(bidderAddressWithBidder, bidder1, "Bidder for bid ID 1 should be bidder 1");
        assertEq(auction.highestBid(), bidAmount, "Highest bid should be bid amount");
        assertEq(unsealedAmount, bidAmount, "Unsealed amount should be bid amount");
    }

    function test_FulfillHighestBid() public {
        // Bidder places a bid
        uint256 bidAmount = 3 ether;
        vm.deal(bidder1, 5 ether);
        vm.startPrank(bidder1);
        uint256 bidID1 = auction.sealedBid{value: auction.reservePrice()}(sealedBidBidder1);
        vm.stopPrank();

        // Move to the auction end block to end the auction
        vm.roll(auction.auctionEndBlock() + 1);

        // Receive the decryption key for the bid id from the timelock contract
        vm.startPrank(auctioneer);

        decryptionSender.fulfilDecryptionRequest(bidID1, decryptionKeyBidder1, signatureBidder1);

        // Reveal the bids
        auction.revealBid(bidID1);

        vm.stopPrank();

        // Bidder fulfills the highest bid
        vm.startPrank(bidder1); // Set bidder1 as the sender
        auction.fulfilHighestBid{value: bidAmount - auction.reservePrice()}();
        vm.stopPrank();

        assert(auction.highestBidPaid());
    }

    function test_WithdrawDeposit() public {
        // Bidder places a bid
        uint256 bidAmount = 3 ether;
        vm.deal(bidder1, 5 ether);
        vm.startPrank(bidder1);
        uint256 bidID1 = auction.sealedBid{value: auction.reservePrice()}(sealedBidBidder1);
        vm.stopPrank();

        // Move to the auction end block to end the auction
        vm.roll(auction.auctionEndBlock() + 1);

        // Receive the decryption key for the bid id from the timelock contract
        vm.startPrank(auctioneer);

        decryptionSender.fulfilDecryptionRequest(bidID1, decryptionKeyBidder1, signatureBidder1);

        // Reveal the bids
        auction.revealBid(bidID1);

        vm.stopPrank();

        // Bidder fulfills the highest bid
        vm.startPrank(bidder1); // Set bidder1 as the sender
        auction.fulfilHighestBid{value: bidAmount - auction.reservePrice()}();
        vm.stopPrank();

        assert(auction.highestBidPaid());

        // Highest bidder cannot withdraw their deposit
        vm.startPrank(bidder1); // Set bidder1 as the sender
        vm.expectRevert("Highest bidder cannot claim the reserve.");
        auction.withdrawDeposit();
        vm.stopPrank();
    }

    function test_WithdrawForfeitedDeposit() public {
        // Bidder places a bid
        vm.deal(bidder1, 5 ether);
        vm.startPrank(bidder1);
        uint256 bidID1 = auction.sealedBid{value: auction.reservePrice()}(sealedBidBidder1);
        vm.stopPrank();

        // Move to the auction end block to end the auction
        vm.roll(auction.auctionEndBlock() + 1);

        // Receive the decryption key for the bid id from the timelock contract
        vm.startPrank(auctioneer);

        decryptionSender.fulfilDecryptionRequest(bidID1, decryptionKeyBidder1, signatureBidder1);

        // Reveal the bids
        auction.revealBid(bidID1);

        vm.stopPrank();

        assert(!auction.highestBidPaid());

        // Bidder1 fails to fulfill the highest bid payment within payment window
        vm.roll(block.number + highestBidPaymentWindowBlocks + 1); // Move past payment deadline

        // Auctioneer can withdraw the forfeited deposit
        vm.startPrank(auctioneer); // Set auctioneer as the sender
        auction.withdrawForfeitedDepositFromHighestBidder();
        vm.stopPrank();
    }
}
