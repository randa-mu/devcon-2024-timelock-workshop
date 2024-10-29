// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

abstract contract SimpleAuctionBase is ReentrancyGuard {
    struct Bid {
        uint256 bidID;
        bytes sealedAmount;
        uint256 unsealedAmount;
        address bidder;
        bool revealed;
    }

    enum AuctionState {
        Ongoing,
        Ended
    }

    AuctionState public auctionState;
    address public auctioneer;
    uint256 public auctionEndBlock;
    uint256 public highestBidPaymentDeadlineBlock;
    uint256 public totalBids;
    uint256 public revealedBidsCount;
    address public highestBidder;
    uint256 public highestBid;
    uint256 public reservePrice;
    bool public highestBidPaid;

    mapping(address => uint256) public depositedReservePrice;
    mapping(uint256 => Bid) public bidsById;
    mapping(address => uint256) public bidderToBidID;

    event NewBid(uint256 bidID, address indexed bidder, bytes sealedAmount);
    event AuctionEnded(address winner, uint256 amount);
    event RevealReceived(uint256 bidID, address bidder, uint256 unsealedAmount);
    event HighestBidFulfilled(address bidder, uint256 amount);
    event ReserveClaimed(address claimant, uint256 amount);
    event ForfeitedReserveClaimed(address auctioneer, uint256 amount);

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
        require(msg.value == reservePrice, "Bid must be exactly equal to the reserve price.");
        _;
    }

    constructor(uint256 durationBlocks, uint256 _reservePrice, uint256 highestBidPaymentWindowBlocks) {
        auctioneer = msg.sender;
        auctionEndBlock = block.number + durationBlocks;
        highestBidPaymentDeadlineBlock = auctionEndBlock + highestBidPaymentWindowBlocks;
        reservePrice = _reservePrice;
        auctionState = AuctionState.Ongoing;
    }

    // ** Setter Functions **

    function depositReserve() external payable {
        require(msg.value == reservePrice, "Deposit must be exactly equal to the reserve price.");
        depositedReservePrice[msg.sender] += msg.value;
    }

    // Override this function in child SimpleAuction contract
    function sealedBid(bytes calldata sealedAmount) internal virtual onlyWhileOngoing {
        // todo convert logic into pseudo code with numbered tasks for workshop
        // after unit tests
        require(depositedReservePrice[msg.sender] >= reservePrice, "Deposit the reserve price before bidding.");

        uint256 bidID = generateBidID(sealedAmount);
        require(bidsById[bidID].bidID == 0, "Bid ID must be unique");

        Bid memory newBid =
            Bid({bidID: bidID, sealedAmount: sealedAmount, unsealedAmount: 0, bidder: msg.sender, revealed: false});

        bidsById[bidID] = newBid;
        bidderToBidID[msg.sender] = bidID;
        totalBids += 1;

        emit NewBid(bidID, msg.sender, sealedAmount);
    }

    function fulfilHighestBid() external payable onlyAfterEnded allBidsUnsealed nonReentrant {
        require(highestBid > 0, "Highest bid is zero");
        require(msg.sender == highestBidder, "Only the highest bidder can complete the payment.");
        require(block.number <= highestBidPaymentDeadlineBlock, "Payment deadline has passed.");
        require(!highestBidPaid, "Payment has already been completed.");
        require(
            msg.value == highestBid - reservePrice, "Payment must be equal to highest bid minus the reserve amount."
        );

        highestBidPaid = true;
        payable(auctioneer).transfer(msg.value + reservePrice);

        emit HighestBidFulfilled(msg.sender, msg.value + reservePrice);
    }

    function claimReservePriceDeposit() external onlyAfterEnded allBidsUnsealed nonReentrant {
        require(msg.sender != highestBidder, "Highest bidder cannot claim the reserve.");
        uint256 depositAmount = depositedReservePrice[msg.sender];
        require(depositAmount > 0, "No reserve amount to claim.");

        depositedReservePrice[msg.sender] = 0;
        payable(msg.sender).transfer(depositAmount);
        emit ReserveClaimed(msg.sender, depositAmount);
    }

    function claimForfeitedReservePriceDeposit() external onlyAuctioneer onlyAfterEnded allBidsUnsealed nonReentrant {
        require(block.number > highestBidPaymentDeadlineBlock, "Payment deadline has not passed.");
        require(!highestBidPaid, "Payment has already been completed.");

        uint256 forfeitedAmount = depositedReservePrice[highestBidder];
        require(forfeitedAmount > 0, "No forfeited reserve to claim.");

        depositedReservePrice[highestBidder] = 0;
        payable(auctioneer).transfer(forfeitedAmount);
        emit ForfeitedReserveClaimed(auctioneer, forfeitedAmount);
    }

    // todo refactor function to be callable by timelock contract only
    function revealBid(uint256 bidID, uint256 unsealedAmount) external onlyAfterEnded {
        require(bidsById[bidID].bidID != 0, "Bid ID does not exist.");
        require(bidsById[bidID].bidder == msg.sender, "Only the bidder can reveal their bid.");
        require(!bidsById[bidID].revealed, "Bid already revealed.");

        bidsById[bidID].unsealedAmount = unsealedAmount;
        bidsById[bidID].revealed = true;
        revealedBidsCount += 1;

        updateHighestBid(bidID, unsealedAmount);
    }

    // ** Internal Functions **

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

    // todo refactor function to return requestID from timelock contract
    function generateBidID(bytes calldata sealedAmount) internal returns (uint256) {
        return uint256(keccak256(abi.encodePacked(sealedAmount)));
    }
}
