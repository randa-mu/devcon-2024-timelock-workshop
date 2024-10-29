// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

abstract contract SimpleAuctionBase {
    address public auctioneer;
    uint256 public auctionEndTime;
    // todo the "highest" variables (highestBidder and highestBid) will only be used after the end of the auction, post decryption of bid amounts
    // todo add decrypt function that takes an array of decrypted values / bytes linked to bid ids
    address public highestBidder;
    uint256 public highestBid;
    uint256 public reservePrice; // todo rename to reserveDeposit
    bool public auctionEnded;
    // window for highest bidder to fulfil the bid, afterwhich auctioneer can claim their reserve deposit.
    uint256 public paymentDeadline;
    bool public paymentCompleted;
    // todo rename to reserveDeposits
    mapping(address => uint256) public deposits; // Reserve deposits by bidders

    enum AuctionState {
        Ongoing,
        Ended
    }

    AuctionState public auctionState;
    // todo encrypt bid amount and emit data needed for offchain timelock encryption
    // people can only bid once so their wallet address can be bid id for offchain purposes

    event NewBid(address indexed bidder, uint256 amount);
    event AuctionEnded(address winner, uint256 amount);
    event ReserveClaimed(address claimant, uint256 amount);
    event PaymentCompleted(address bidder, uint256 amount);
    event ForfeitedReserveClaimed(address auctioneer, uint256 amount);

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
    // todo use blocks for auction duration and to sync with offchain timelock easily

    constructor(uint256 durationMinutes, uint256 _reservePrice, uint256 paymentWindowMinutes) {
        auctioneer = msg.sender;
        auctionEndTime = block.timestamp + (durationMinutes * 1 minutes);
        reservePrice = _reservePrice;
        auctionState = AuctionState.Ongoing;
        auctionEnded = false;
        paymentCompleted = false;
        paymentDeadline = auctionEndTime + (paymentWindowMinutes * 1 minutes);
    }

    function depositReserve() external payable {
        require(msg.value == reservePrice, "Deposit must be exactly equal to the reserve price.");
        deposits[msg.sender] += msg.value;
    }

    function bid() external payable onlyWhileOngoing {
        require(deposits[msg.sender] >= reservePrice, "You must deposit the reserve price before bidding.");
        // todo task - change logic to match interface for timelock
        // we can have base contract with correct logic as virtual with
        // pseudo code comments but not fully implemented
        // have a toggle in README with correct logic
        require(msg.value > highestBid, "Bid must be higher than the current highest bid.");

        // todo when bidding, no payments made, and no refunds.
        // they simply indicate an amount which will be encrypted and emitted in an event
        // Refund the previous highest bidder if there is one
        if (highestBidder != address(0)) {
            // Send the highest bid back to the previous highest bidder
            payable(highestBidder).transfer(highestBid);
        }

        // todo these variables are not used during timelock window till end of auction.
        // just store bid information and timelocked bid
        highestBidder = msg.sender;
        highestBid = msg.value;

        emit NewBid(msg.sender, msg.value);
    }

    // todo task - called after timelock
    function endAuction() external onlyAuctioneer onlyAfterEnded {
        auctionState = AuctionState.Ended;
        auctionEnded = true;
        // todo this logic is useful only after timelock
        if (highestBid > 0) {
            // Transfer the highest bid amount to the auctioneer
            // todo no payment made till highest bidder is known after timelock and they
            // fulfil their bid by paying
            payable(auctioneer).transfer(highestBid);
            emit AuctionEnded(highestBidder, highestBid);
        } else {
            emit AuctionEnded(address(0), 0); // No valid bids
        }
    }

    // todo called at the end of auction
    // todo add a window after the auction within which the highest bidder has to complete payment
    // if they do not complete after this window, auctioneer can claim their reserve deposit
    function completePayment() external payable {
        require(auctionEnded, "Auction is still ongoing.");
        require(msg.sender == highestBidder, "Only the highest bidder can complete the payment.");
        require(block.timestamp <= paymentDeadline, "Payment deadline has passed.");
        require(!paymentCompleted, "Payment has already been completed.");
        require(
            msg.value == highestBid - reservePrice, "Payment must be equal to highest bid minus the reserve amount."
        );

        paymentCompleted = true;

        // Transfer the payment to the auctioneer
        payable(auctioneer).transfer(msg.value + reservePrice);

        emit PaymentCompleted(msg.sender, msg.value + reservePrice);
    }

    // todo task - we will only know highest bidder and highest bid after timelock
    function claimReserve() external {
        require(auctionEnded, "Auction is still ongoing.");
        require(msg.sender != highestBidder, "Highest bidder cannot claim the reserve.");
        uint256 depositAmount = deposits[msg.sender];

        require(depositAmount > 0, "No reserve amount to claim.");

        // Reset the deposit for the claimant
        deposits[msg.sender] = 0;

        // Refund the reserve deposit to non-winning bidders
        payable(msg.sender).transfer(depositAmount);
        emit ReserveClaimed(msg.sender, depositAmount);
    }

    function claimForfeitedReserve() external onlyAuctioneer {
        require(auctionEnded, "Auction is still ongoing.");
        require(block.timestamp > paymentDeadline, "Payment deadline has not passed.");
        require(!paymentCompleted, "Payment has already been completed.");

        uint256 forfeitedAmount = deposits[highestBidder];
        require(forfeitedAmount > 0, "No forfeited reserve to claim.");

        // Reset the deposit for the highest bidder
        deposits[highestBidder] = 0;

        // Transfer the forfeited reserve to the auctioneer
        payable(auctioneer).transfer(forfeitedAmount);
        emit ForfeitedReserveClaimed(auctioneer, forfeitedAmount);
    }

    // todo the functions below should return zero values till after timelock
    function getHighestBid() external view returns (uint256) {
        return highestBid;
    }

    function getHighestBidder() external view returns (address) {
        return highestBidder;
    }
}
