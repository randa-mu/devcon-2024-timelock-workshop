// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SimpleAuctionBase} from "./SimpleAuctionBase.sol";

contract SimpleAuction is SimpleAuctionBase {
    constructor(
        uint256 durationBlocks,
        uint256 reservePrice,
        uint256 highestBidPaymentWindowBlocks,
        address timelockContract
    ) SimpleAuctionBase(durationBlocks, reservePrice, highestBidPaymentWindowBlocks, timelockContract) {}

    /**
     * @notice Submits a sealed bid in the ongoing auction, uniquely identified and linked to the sender.
     *
     * @dev This function accepts a sealed bid amount as input, generates a unique bid ID,
     *      and stores the bid details for future unsealing. The function can only be called
     *      while the auction is ongoing, and the caller must send an exact reserve price as
     *      `msg.value`. The generated bid ID must be unique.
     *      The function utilizes the `onlyWhileOngoing` and `meetsExactReservePrice` modifiers
     *      to enforce bid submission timing and payment accuracy.
     *
     * Requirements:
     * - `onlyWhileOngoing`: Auction must still be open for bidding.
     * - `meetsExactReservePrice`: Caller must send the exact reserve price with the bid.
     * - Unique `bidID`: Each sealed bid must have a unique ID, generated based on `sealedAmount`.
     *
     * Effects:
     * - Generates a unique `bidID` using the `sealedAmount` input.
     * - Creates and stores a new `Bid` struct with `sealedAmount`, `decryptionKey`, `unsealedAmount`,
     *   `bidder` (msg.sender), and `revealed` status.
     * - Maps the new bid to `bidsById[bidID]` for retrieval by ID and associates it to the
     *   `msg.sender` in `bidderToBidID`.
     * - Updates `depositedReservePrice` with the reserve price amount sent by `msg.sender` to enable refunds.
     * - Increments the total bid count (`totalBids`).
     *
     * Emits:
     * - `NewBid`: Emitted when a new bid is successfully submitted, containing the `bidID`, `msg.sender`,
     *   and `sealedAmount`.
     *
     * @param sealedAmount A `bytes` value representing the hashed or encrypted bid amount, ensuring bid privacy.
     * @return bidID The unique identifier generated for the submitted bid.
     */
    function sealedBid(bytes calldata sealedAmount)
        external
        payable
        override
        onlyWhileOngoing
        meetsExactReservePrice
        returns (uint256)
    {
        // todo convert `generate bid id with sealed amount input` part to task
        // Generate a unique bid ID based on the sealed amount
        uint256 bidID = generateBidID(sealedAmount);
        // Check that the bid ID does not already exist to enforce uniqueness
        require(bidsById[bidID].bidID == 0, "Bid ID must be unique");
        // Create a new bid with the given parameters
        Bid memory newBid = Bid({
            bidID: bidID,
            sealedAmount: sealedAmount,
            decryptionKey: hex"",
            unsealedAmount: 0,
            bidder: msg.sender,
            revealed: false
        });
        // Store the new bid in the bidsById and bidderToBidID mappings for tracking and retrieval
        bidsById[bidID] = newBid;
        bidderToBidID[msg.sender] = bidID;
        // Track the reserve deposit for refund purposes
        depositedReservePrice[msg.sender] += msg.value;
        // Increment the total bid count
        totalBids += 1;
        // emit NewBid event
        emit NewBid(bidID, msg.sender, sealedAmount);
        // return the bidID
        return bidID;
    }
}
