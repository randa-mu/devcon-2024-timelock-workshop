// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract SimpleAuction {
    address public auctioneer;
    uint public auctionEndTime;
    address public highestBidder;
    uint public highestBid;
    uint public reservePrice;
    bool public auctionEnded;

    mapping(address => uint) public deposits; // Reserve deposits by bidders

    enum AuctionState { Ongoing, Ended }
    AuctionState public auctionState;

    event NewBid(address indexed bidder, uint amount);
    event AuctionEnded(address winner, uint amount);
    event ReserveClaimed(address claimant, uint amount);

    modifier onlyAuctioneer() {
        require(msg.sender == auctioneer, "Only the auctioneer can call this.");
        _;
    }

    modifier onlyWhileOngoing() {
        require(block.timestamp < auctionEndTime, "Auction has already ended.");
        _;
    }

    modifier onlyAfterEnded() {
        require(block.timestamp >= auctionEndTime, "Auction is still ongoing.");
        _;
    }

    modifier meetsExactReservePrice() {
        require(msg.value == reservePrice, "Bid must be exactly equal to the reserve price.");
        _;
    }

    constructor(uint durationMinutes, uint _reservePrice) {
        auctioneer = msg.sender;
        auctionEndTime = block.timestamp + (durationMinutes * 1 minutes);
        reservePrice = _reservePrice;
        auctionState = AuctionState.Ongoing;
        auctionEnded = false;
    }

    function depositReserve() external payable {
        require(msg.value == reservePrice, "Deposit must be exactly equal to the reserve price.");
        deposits[msg.sender] += msg.value;
    }

    function bid() external payable onlyWhileOngoing {
        require(deposits[msg.sender] >= reservePrice, "You must deposit the reserve price before bidding.");
        require(msg.value > highestBid, "Bid must be higher than the current highest bid.");

        // Refund the previous highest bidder if there is one
        if (highestBidder != address(0)) {
            // Send the highest bid back to the previous highest bidder
            payable(highestBidder).transfer(highestBid);
        }

        highestBidder = msg.sender;
        highestBid = msg.value;

        emit NewBid(msg.sender, msg.value);
    }

    function endAuction() external onlyAuctioneer onlyAfterEnded {
        auctionState = AuctionState.Ended;
        auctionEnded = true;

        if (highestBid > 0) {
            // Transfer the highest bid amount to the auctioneer
            payable(auctioneer).transfer(highestBid);
            emit AuctionEnded(highestBidder, highestBid);
        } else {
            emit AuctionEnded(address(0), 0); // No valid bids
        }
    }

    function claimReserve() external {
        require(auctionEnded, "Auction is still ongoing.");
        uint depositAmount = deposits[msg.sender];

        require(depositAmount > 0, "No reserve amount to claim.");

        // Reset the deposit for the claimant
        deposits[msg.sender] = 0;

        // If the user is not the highest bidder, refund their reserve amount
        if (msg.sender != highestBidder) {
            payable(msg.sender).transfer(depositAmount);
            emit ReserveClaimed(msg.sender, depositAmount);
        }
    }

    function completePayment() external payable {
        require(auctionEnded, "Auction is still ongoing.");
        require(msg.sender == highestBidder, "Only the highest bidder can complete the payment.");
        require(msg.value == highestBid - reservePrice, "Payment must be equal to highest bid minus the reserve amount.");

        // Reset the highest bidder
        highestBidder = address(0);
        highestBid = 0;

        // Send the funds to the auctioneer
        payable(auctioneer).transfer(msg.value + reservePrice);
    }

    function getHighestBid() external view returns (uint) {
        return highestBid;
    }

    function getHighestBidder() external view returns (address) {
        return highestBidder;
    }
}
