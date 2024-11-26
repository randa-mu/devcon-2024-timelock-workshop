// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TypesLib} from "./lib/TypesLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBlocklockSender} from "./interfaces/IBlocklockSender.sol";
import {IBlocklockReceiver} from "./interfaces/IBlocklockReceiver.sol";

/// @title SimpleAuctionBase - Abstract Base Contract for a Sealed Bid Auction
/// @dev This contract manages the core logic of a sealed bid auction with a reserve price requirement.
abstract contract SimpleAuctionBase is IBlocklockReceiver, ReentrancyGuard {
    struct Bid {
        uint256 bidID; // Unique identifier for the bid
        TypesLib.Ciphertext sealedAmount; // Encrypted / sealed bid amount
        bytes decryptionKey; // The timelock decryption key used to unseal the sealed bid
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
    IBlocklockSender public timelock; // The timelock contract which we will be used to decrypt data at specific block
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
    event NewBid(uint256 indexed bidID, address indexed bidder, TypesLib.Ciphertext sealedAmount);
    event AuctionEnded(address indexed winner, uint256 amount);
    event BidUnsealed(uint256 indexed bidID, address bidder, uint256 unsealedAmount);
    event HighestBidFulfilled(address indexed bidder, uint256 amount);
    event ReserveClaimed(address indexed claimant, uint256 amount);
    event ForfeitedReserveClaimed(address auctioneer, uint256 amount);
    event DecryptionKeyReceived(uint256 indexed bidID, bytes decryptionKey);

    // ** Modifiers **
    modifier onlyTimelockContract() {
        require(msg.sender == address(timelock), "Only timelock contract can call this.");
        _;
    }

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

    modifier onlyAfterBidsUnsealed() {
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
    /// @param timelockContract The address of the timelock encryption smart contract
    constructor(
        uint256 durationBlocks,
        uint256 _reservePrice,
        uint256 highestBidPaymentWindowBlocks,
        address timelockContract
    ) {
        auctioneer = msg.sender;
        auctionEndBlock = block.number + durationBlocks;
        highestBidPaymentDeadlineBlock = auctionEndBlock + highestBidPaymentWindowBlocks;
        reservePrice = _reservePrice;
        auctionState = AuctionState.Ongoing;
        timelock = IBlocklockSender(timelockContract);
    }

    // ** Setter Functions **

    /**
     * @notice Allows participants to submit a sealed bid during the ongoing auction.
     *
     * @dev This function accepts a sealed bid, represented as an encrypted value,
     *      to maintain bid confidentiality. The function requires the caller to send an
     *      exact reserve price with the bid, which is held for deposit and refunded if
     *      the bid is not the highest. This is a virtual function intended to be
     *      overridden in a derived contract.
     *
     * Requirements:
     * - `onlyWhileOngoing`: The auction must be in an open state, allowing bid submissions.
     * - `meetsExactReservePrice`: Caller must send the reserve price as `msg.value` to ensure
     *   the bid meets the minimum requirement.
     *
     * Returns:
     * - A unique `uint256` bid ID to represent and retrieve the bid.
     *
     * @param sealedAmount A `bytes` value that represents the caller’s encrypted bid amount,
     *        which conceals the actual bid until it is unsealed later.
     * @return uint256 A unique identifier (`bidID`) generated for tracking the bid.
     */
    function sealedBid(TypesLib.Ciphertext calldata sealedAmount)
        external
        payable
        virtual
        onlyWhileOngoing
        meetsExactReservePrice
        returns (uint256)
    {}

    /**
     * @notice Completes the highest bid payment and transfers funds to the auctioneer.
     *
     * @dev This function is called by the highest bidder to finalize the payment for their winning bid.
     *      It can only be executed after the auction has ended, all bids have been unsealed,
     *      and before the specified payment deadline block. The highest bidder must pay the exact
     *      amount of the highest bid minus the reserve price. Reentrancy is prevented with the
     *      `nonReentrant` modifier to secure fund transfer.
     *
     * Requirements:
     * - `onlyAfterEnded`: The auction must have concluded.
     * - `onlyAfterBidsUnsealed`: All bids must have been unsealed.
     * - `nonReentrant`: Reentrancy protection is enabled.
     * - `highestBid > 0`: There must be a valid highest bid amount.
     * - `msg.sender == highestBidder`: Only the highest bidder can complete the payment.
     * - `block.number <= highestBidPaymentDeadlineBlock`: The payment must be made before the deadline.
     * - `!highestBidPaid`: Payment must not have been completed previously.
     * - `msg.value == highestBid - reservePrice`: The payment amount must equal the highest bid minus the reserve price.
     *
     * Effects:
     * - Marks `highestBidPaid` as true to indicate that the payment has been fulfilled.
     * - Transfers the combined amount of `msg.value` and `reservePrice` to the auctioneer.
     *
     * Emits:
     * - `HighestBidFulfilled`: Emitted when the highest bid is successfully paid and transferred to the auctioneer,
     *   including `msg.sender` (the highest bidder) and the total amount transferred.
     */
    function fulfilHighestBid() external payable onlyAfterEnded onlyAfterBidsUnsealed nonReentrant {
        require(highestBid > 0, "Highest bid is zero.");
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

    /**
     * @notice Allows non-winning bidders to withdraw their reserve deposits after the auction ends.
     *
     * @dev This function enables bidders, except for the highest bidder, to reclaim their reserve
     *      deposit after the auction has ended and all bids have been unsealed. The reserve amount
     *      stored in `depositedReservePrice` is reset to zero before transferring funds to prevent
     *      reentrancy risks. Reentrancy protection is enforced using the `nonReentrant` modifier.
     *
     * Requirements:
     * - `onlyAfterEnded`: The auction must be concluded.
     * - `onlyAfterBidsUnsealed`: All bids must be unsealed.
     * - `nonReentrant`: Protects against reentrancy attacks.
     * - `msg.sender != highestBidder`: Only non-winning bidders can claim their reserve deposit.
     * - `depositedReservePrice[msg.sender] > 0`: The caller must have a positive reserve deposit amount.
     *
     * Effects:
     * - Sets `depositedReservePrice[msg.sender]` to zero, indicating the deposit has been withdrawn.
     * - Transfers the deposit amount to the caller's address.
     *
     * Emits:
     * - `ReserveClaimed`: Emitted when a reserve deposit is successfully withdrawn, including the caller's
     *   address (`msg.sender`) and the amount transferred (`depositAmount`).
     */
    function withdrawDeposit() external onlyAfterEnded onlyAfterBidsUnsealed nonReentrant {
        require(msg.sender != highestBidder, "Highest bidder cannot claim the reserve.");
        uint256 depositAmount = depositedReservePrice[msg.sender];
        require(depositAmount > 0, "No reserve amount to claim.");

        depositedReservePrice[msg.sender] = 0;
        payable(msg.sender).transfer(depositAmount);
        emit ReserveClaimed(msg.sender, depositAmount);
    }

    /**
     * @notice Withdraws the forfeited reserve deposit of the highest bidder if they fail to pay on time.
     *
     * @dev This function can only be called by the auctioneer after the auction has ended,
     *      all bids are unsealed, and the highest bid payment deadline has passed without payment.
     *      Reentrancy is prevented with `nonReentrant` modifier.
     *
     * Requirements:
     * - The caller must be the auctioneer.
     * - The auction must be over, and bids must be unsealed.
     * - The highest bid payment deadline must have passed.
     * - `highestBidPaid` must be false (i.e., payment has not been completed).
     *
     * Emits:
     * - `ForfeitedReserveClaimed`: Logs the auctioneer and forfeited reserve amount.
     */
    function withdrawForfeitedDepositFromHighestBidder()
        external
        onlyAuctioneer
        onlyAfterEnded
        onlyAfterBidsUnsealed
        nonReentrant
    {
        require(block.number > highestBidPaymentDeadlineBlock, "Payment deadline has not passed.");
        require(!highestBidPaid, "Payment has already been completed.");

        uint256 forfeitedAmount = depositedReservePrice[highestBidder];
        require(forfeitedAmount > 0, "No forfeited reserve to claim.");

        depositedReservePrice[highestBidder] = 0;
        payable(auctioneer).transfer(forfeitedAmount);
        emit ForfeitedReserveClaimed(auctioneer, forfeitedAmount);
    }

    /**
     * @notice Receives and stores the decryption key for a bid from the timelock contract.
     *
     * @dev Called by the timelock contract after the auction ends to store the decryption key for a specific bid.
     *
     * Requirements:
     * - The caller must be the defined timelock contract.
     * - The auction must have ended or auction end block reached.
     * - The bid ID must be valid and have no decryption key yet recorded.
     *
     * Emits:
     * - `DecryptionKeyReceived`: Logs the `requestID` and the provided `decryptionKey`.
     *
     * @param requestID The unique identifier for the bid to associate the decryption key with.
     * @param decryptionKey The bytes key used to unseal the bid.
     */
    function receiveBlocklock(uint256 requestID, bytes calldata decryptionKey)
        external
        onlyAfterEnded
        onlyTimelockContract
    {
        require(bidsById[requestID].bidID != 0, "Bid ID does not exist.");
        require(
            bidsById[requestID].decryptionKey.length == 0, "Bid decryption key already received from timelock contract."
        );
        Bid storage bid = bidsById[requestID];
        bid.decryptionKey = decryptionKey;

        uint256 decryptedSealedBidAmount = abi.decode(timelock.decrypt(bid.sealedAmount, decryptionKey), (uint256));
        bid.unsealedAmount = decryptedSealedBidAmount;

        emit DecryptionKeyReceived(requestID, decryptionKey);
    }

    /**
     * @notice Reveals a sealed bid by setting its unsealed amount and updating the highest bid if applicable.
     *
     * @dev Allows a bidder to reveal their bid, provided the bid has a valid decryption key.
     *
     * Requirements:
     * - The bid ID must exist.
     * - The bid must not have been previously revealed.
     * - The bid must have a decryption key.
     *
     * @param bidID The unique identifier for the bid to be revealed.
     * @param unsealedAmount The actual bid amount to be revealed.
     */
    function revealBid(uint256 bidID, uint256 unsealedAmount) external onlyAuctioneer {
        require(bidsById[bidID].bidID != 0, "Bid ID does not exist.");
        require(!bidsById[bidID].revealed, "Bid already revealed.");
        require(bidsById[bidID].decryptionKey.length > 0, "Bid decryption key not received from timelock contract.");

        updateHighestBid(bidID, unsealedAmount);
    }

    // ** Internal Functions **

    /**
     * @notice Updates the highest bid if the unsealed amount of the revealed bid exceeds the current highest bid.
     *
     * @dev Internal function called by `revealBid` to compare and update the highest bid if required.
     *
     * @param bidID The unique identifier of the revealed bid.
     * @param unsealedAmount The actual bid amount to compare with the current highest bid.
     */
    function updateHighestBid(uint256 bidID, uint256 unsealedAmount) internal {
        Bid storage bid = bidsById[bidID];

        bid.unsealedAmount = unsealedAmount;
        bid.revealed = true;
        revealedBidsCount += 1;

        if (unsealedAmount > highestBid && unsealedAmount > reservePrice) {
            highestBid = unsealedAmount;
            highestBidder = bid.bidder;
        }

        emit BidUnsealed(bidID, bid.bidder, unsealedAmount);
    }

    /**
     * @notice Ends the auction, setting the auction state to "Ended" and emitting the `AuctionEnded` event.
     *
     * @dev Can only be called by the auctioneer once the auction end block has reached.
     *
     * Emits:
     * - `AuctionEnded`: Logs the highest bidder and the highest bid amount.
     */
    function endAuction() external onlyAuctioneer onlyAfterEnded {
        auctionState = AuctionState.Ended;
        emit AuctionEnded(highestBidder, highestBid);
    }

    // ** Getter Functions **

    /**
     * @notice Returns the highest bid amount.
     *
     * @return The current highest bid amount.
     */
    function getHighestBid() external view returns (uint256) {
        return highestBid;
    }

    /**
     * @notice Returns the address of the highest bidder.
     *
     * @return The address of the current highest bidder.
     */
    function getHighestBidder() external view returns (address) {
        return highestBidder;
    }

    /**
     * @notice Retrieves bid information associated with a specific bidder.
     *
     * @param bidder The address of the bidder.
     * @return sealedAmount The sealed bid as bytes.
     * @return decryptionKey The decryption key used to decrypt the ciphertext off-chain.
     * @return unsealedAmount The unsealed ciphertext representing the sealed bid.
     * @return _bidder The address of the bidder.
     * @return revealed A boolean indicating if the sealed bid has been unsealed or revealed.
     */
    function getBidWithBidder(address bidder)
        external
        view
        returns (
            TypesLib.Ciphertext memory sealedAmount,
            bytes memory decryptionKey,
            uint256 unsealedAmount,
            address _bidder,
            bool revealed
        )
    {
        sealedAmount = bidsById[bidderToBidID[bidder]].sealedAmount;
        decryptionKey = bidsById[bidderToBidID[bidder]].decryptionKey;
        unsealedAmount = bidsById[bidderToBidID[bidder]].unsealedAmount;
        _bidder = bidsById[bidderToBidID[bidder]].bidder;
        revealed = bidsById[bidderToBidID[bidder]].revealed;
    }

    /**
     * @notice Retrieves bid information for a given bid ID.
     *
     * @param bidID The unique identifier for the bid.
     * @return sealedAmount The sealed bid as bytes.
     * @return decryptionKey The decryption key used to decrypt the ciphertext off-chain.
     * @return unsealedAmount The unsealed ciphertext representing the sealed bid.
     * @return bidder The address of the bidder.
     * @return revealed A boolean indicating if the sealed bid has been unsealed or revealed.
     */
    function getBidWithBidID(uint256 bidID)
        external
        view
        returns (
            TypesLib.Ciphertext memory sealedAmount,
            bytes memory decryptionKey,
            uint256 unsealedAmount,
            address bidder,
            bool revealed
        )
    {
        sealedAmount = bidsById[bidID].sealedAmount;
        decryptionKey = bidsById[bidID].decryptionKey;
        unsealedAmount = bidsById[bidID].unsealedAmount;
        bidder = bidsById[bidID].bidder;
        revealed = bidsById[bidID].revealed;
    }

    // ** Internal Utilities **

    /**
     * @notice Generates a unique bid ID based on the provided sealed amount and requests a blocklock from the timelock contract.
     *
     * @dev Called internally during bid submission to create a bid ID that is locked until unsealing.
     *
     * @param sealedAmount The encrypted value of the bid amount.
     * @return The unique identifier for the generated bid.
     */
    function generateBidID(TypesLib.Ciphertext calldata sealedAmount) internal returns (uint256) {
        uint256 bidID = timelock.requestBlocklock(auctionEndBlock, sealedAmount);
        return bidID;
    }
}
