// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SimpleAuctionBase - Abstract Base Contract for a Sealed Bid Auction
/// @dev This contract manages the core logic of a sealed bid auction with a reserve price requirement.
abstract contract SimpleAuctionBase is ReentrancyGuard {
    struct Bid {
        uint256 bidID; // Unique identifier for the bid
        bytes sealedAmount; // Encrypted/sealed bid amount
        uint256 unsealedAmount; // Decrypted/unsealed bid amount, revealed after auction end
        address bidder; // Address of the bidder
        bool revealed; // Status of whether the bid has been revealed
    }

    /// @dev Enum representing the auction state
    enum AuctionState {
        Ongoing, // Auction is currently active
        Ended // Auction has ended
    }

    // ** State Variables **
    AuctionState public auctionState; // Current state of the auction
    address public auctioneer; // Address of the auctioneer who initiates the auction
    uint256 public auctionEndBlock; // Block number when the auction ends
    uint256 public highestBidPaymentDeadlineBlock; // Deadline for highest bid payment after auction end
    uint256 public totalBids; // Total number of bids placed
    uint256 public revealedBidsCount; // Count of revealed bids after auction end
    address public highestBidder; // Address of the highest bidder
    uint256 public highestBid; // Highest unsealed bid amount
    uint256 public reservePrice; // Minimum bid amount required to be deposited before placing a bid
    bool public highestBidPaid; // Status indicating whether the highest bid payment has been completed

    mapping(address => uint256) public depositedReservePrice; // Reserve deposits for each bidder
    mapping(uint256 => Bid) public bidsById; // Mapping of bid IDs to bid details
    mapping(address => uint256) public bidderToBidID; // Mapping of bidders to their bid IDs

    // ** Events **
    event NewBid(uint256 bidID, address indexed bidder, bytes sealedAmount);
    event AuctionEnded(address winner, uint256 amount);
    event RevealReceived(uint256 bidID, address bidder, uint256 unsealedAmount);
    event HighestBidFulfilled(address bidder, uint256 amount);
    event ReserveClaimed(address claimant, uint256 amount);
    event ForfeitedReserveClaimed(address auctioneer, uint256 amount);

    // ** Modifiers **
    modifier onlyAuctioneer() {
        require(msg.sender == auctioneer, "Only auctioneer can call this.");
        _;
    }

    modifier onlyWhileOngoing() {
        require(block.number < auctionEndBlock, "Auction has already ended.");
        _;
    }

    modifier onlyAfterEnded() {
        require(block.number >= auctionEndBlock, "Auction is still ongoing.");
        _;
    }

    modifier allBidsUnsealed() {
        require(revealedBidsCount == totalBids, "Not all bids have been revealed.");
        _;
    }

    modifier meetsExactReservePrice() {
        require(msg.value == reservePrice, "Bid must be accompanied by a deposit equal to the reserve price.");
        _;
    }

    // ** Constructor **
    /// @param durationBlocks Number of blocks for which the auction will be active
    /// @param _reservePrice The minimum amount required as a reserve price for each bid
    /// @param highestBidPaymentWindowBlocks Number of blocks allowed for the highest bid payment after auction end
    constructor(uint256 durationBlocks, uint256 _reservePrice, uint256 highestBidPaymentWindowBlocks) {
        auctioneer = msg.sender;
        auctionEndBlock = block.number + durationBlocks;
        highestBidPaymentDeadlineBlock = auctionEndBlock + highestBidPaymentWindowBlocks;
        reservePrice = _reservePrice;
        auctionState = AuctionState.Ongoing;
    }

    // ** Setter Functions **

    /// @notice Places a sealed bid, with the bid amount encrypted in `sealedAmount`
    /// @notice Bidders need to deposit the exact reserve price before placing a sealed bid
    /// @dev To be overridden by child contract to implement full bid sealing logic
    /// @param sealedAmount The encrypted bid amount
    function sealedBid(bytes calldata sealedAmount) internal virtual onlyWhileOngoing meetsExactReservePrice {
        // todo convert logic into pseudo code with numbered tasks for workshop
        // after unit tests
        
        // Generate a unique bid ID based on the sealed amount
        uint256 bidID = generateBidID(sealedAmount);
        // Check that the bid ID does not already exist to enforce uniqueness
        require(bidsById[bidID].bidID == 0, "Bid ID must be unique");
        // Create a new bid with the given parameters
        Bid memory newBid = Bid({
            bidID: bidID, 
            sealedAmount: sealedAmount, 
            unsealedAmount: 0, 
            bidder: msg.sender, 
            revealed: false
        });
        // Store the bid in mappings for tracking and retrieval
        bidsById[bidID] = newBid;
        bidderToBidID[msg.sender] = bidID;
        // Track the reserve deposit for refund purposes
        depositedReservePrice[msg.sender] += msg.value;
        // Increment the total bid count
        totalBids += 1;

        emit NewBid(bidID, msg.sender, sealedAmount);
    }

    /// @notice Allows the highest bidder to complete payment after auction ends and all bids are revealed
    function fulfilHighestBid() external payable onlyAfterEnded allBidsUnsealed nonReentrant {
        require(highestBid > 0, "Highest bid is zero");
        require(msg.sender == highestBidder, "Only the highest bidder can complete the payment.");
        require(block.number <= highestBidPaymentDeadlineBlock, "Payment deadline has passed.");
        require(!highestBidPaid, "Payment has already been completed.");
        require(msg.value == highestBid - reservePrice, "Payment must be equal to highest bid minus the reserve amount.");

        highestBidPaid = true;
        payable(auctioneer).transfer(msg.value + reservePrice);

        emit HighestBidFulfilled(msg.sender, msg.value + reservePrice);
    }

    /// @notice Allows non-winning bidders to reclaim their reserve price deposits after auction ends
    function claimReservePriceDeposit() external onlyAfterEnded allBidsUnsealed nonReentrant {
        require(msg.sender != highestBidder, "Highest bidder cannot claim the reserve.");
        uint256 depositAmount = depositedReservePrice[msg.sender];
        require(depositAmount > 0, "No reserve amount to claim.");

        depositedReservePrice[msg.sender] = 0;
        payable(msg.sender).transfer(depositAmount);
        emit ReserveClaimed(msg.sender, depositAmount);
    }

    /// @notice Allows auctioneer to claim forfeited reserve price if highest bidder fails to complete payment
    function claimForfeitedReservePriceDeposit() external onlyAuctioneer onlyAfterEnded allBidsUnsealed nonReentrant {
        require(block.number > highestBidPaymentDeadlineBlock, "Payment deadline has not passed.");
        require(!highestBidPaid, "Payment has already been completed.");

        uint256 forfeitedAmount = depositedReservePrice[highestBidder];
        require(forfeitedAmount > 0, "No forfeited reserve to claim.");

        depositedReservePrice[highestBidder] = 0;
        payable(auctioneer).transfer(forfeitedAmount);
        emit ForfeitedReserveClaimed(auctioneer, forfeitedAmount);
    }

    /// @notice Reveals the unsealed bid amount after auction ends
    function revealBid(uint256 bidID, uint256 unsealedAmount) external onlyAfterEnded {
        // todo refactor function to be callable by timelock contract only
        require(bidsById[bidID].bidID != 0, "Bid ID does not exist.");
        require(bidsById[bidID].bidder == msg.sender, "Only the bidder can reveal their bid.");
        require(!bidsById[bidID].revealed, "Bid already revealed.");

        bidsById[bidID].unsealedAmount = unsealedAmount;
        bidsById[bidID].revealed = true;
        revealedBidsCount += 1;

        updateHighestBid(bidID, unsealedAmount);
    }

    // ** Internal Functions **

    /// @notice Updates the highest bid if the revealed bid is greater than the current highest
    /// @param bidID The bid ID of the revealed bid
    /// @param unsealedAmount The unsealed bid amount
    function updateHighestBid(uint256 bidID, uint256 unsealedAmount) internal {
        Bid storage bid = bidsById[bidID];
        require(bid.bidID != 0, "Bid ID does not exist.");
        require(!bid.revealed, "Bid already revealed.");

        bid.unsealedAmount = unsealedAmount;
        bid.revealed = true;
        revealedBidsCount += 1;

        if (unsealedAmount > highestBid) {
            highestBid = unsealedAmount;
            highestBidder = bid.bidder;
        }

        emit RevealReceived(bidID, bid.bidder, unsealedAmount);
    }

    /// @notice Ends the auction and records the highest bid as final
    function endAuction() external onlyAuctioneer onlyAfterEnded {
        auctionState = AuctionState.Ended;
        emit AuctionEnded(highestBidder, highestBid);
    }

    // ** Getter Functions **

    function getHighestBid() external view returns (uint256) {
        return highestBid;
    }

    function getHighestBidder() external view returns (address) {
        return highestBidder;
    }

    // ** Internal Utilities **

    /// @notice Generates a unique ID for the bid based on the sealed amount
    /// @param sealedAmount The sealed (encrypted) bid amount
    /// @return A unique bid identifier
    function generateBidID(bytes calldata sealedAmount) internal returns (uint256) {
        // todo refactor function to return requestID from timelock contract
        return uint256(keccak256(abi.encodePacked(sealedAmount)));
    }
}
