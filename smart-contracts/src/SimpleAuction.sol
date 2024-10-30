// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SimpleAuctionBase} from "./SimpleAuctionBase.sol";

contract SimpleAuction is SimpleAuctionBase {
    constructor(uint256 durationBlocks, uint256 _reservePrice, uint256 highestBidPaymentWindowBlocks)
        SimpleAuctionBase(durationBlocks, _reservePrice, highestBidPaymentWindowBlocks)
    {}

    /// @notice Places a sealed bid, with the bid amount encrypted in `sealedAmount`
    /// @notice Bidders need to deposit the exact reserve price before placing a sealed bid
    /// @dev To be overridden by child contract to implement full bid sealing logic
    /// @param sealedAmount The encrypted bid amount
    function sealedBid(bytes calldata sealedAmount) external payable override onlyWhileOngoing meetsExactReservePrice returns (uint256) {
        // todo convert parts of this logic into pseudo code with numbered tasks for workshop
        // Generate a unique bid ID based on the sealed amount
        uint256 bidID = generateBidID(sealedAmount);
        // Check that the bid ID does not already exist to enforce uniqueness
        require(bidsById[bidID].bidID == 0, "Bid ID must be unique");
        // Create a new bid with the given parameters
        Bid memory newBid =
            Bid({bidID: bidID, sealedAmount: sealedAmount, unsealedAmount: 0, bidder: msg.sender, revealed: false});
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
