// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../lib/TypesLib.sol";

import {IBlocklockSender} from "../interfaces/IBlocklockSender.sol";
import {IBlocklockReceiver} from "../interfaces/IBlocklockReceiver.sol";
import {ISignatureSender} from "../interfaces/ISignatureSender.sol";

import {SignatureReceiverBase} from "../signature-requests/SignatureReceiverBase.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract BlocklockSender is IBlocklockSender, SignatureReceiverBase, AccessControl {
    string public constant SCHEME_ID = "BN254-BLS-BLOCKLOCK";

    // Request identifiers
    uint256 public lastRequestID = 0;

    // Mapping from signature requestID to blocklock requestID(s)
    mapping(uint256 => uint256[]) public signaturesToBlocklock;

    // Mapping from blockHeight to signature requestID
    mapping(uint256 => uint256) public signatureRequests;

    // Mapping from blocklock requestID to blocklock request details
    mapping(uint256 => TypesLib.BlocklockRequest) public blocklockRequests;

    event BlocklockRequested(
        uint256 indexed requestID,
        uint256 indexed signatureRequestID,
        uint256 blockHeight,
        bytes ciphertext,
        address indexed requester,
        uint256 requestedAt
    );
    event BlocklockCallbackSuccess(
        uint256 indexed requestID,
        uint256 indexed signatureRequestID,
        uint256 blockHeight,
        bytes ciphertext,
        bytes signature
    );
    event BlocklockCallbackFailed(
        uint256 indexed requestID, uint256 indexed signatureRequestID, uint256 blockHeight, bytes signature
    );

    constructor(address _signatureSender) SignatureReceiverBase(_signatureSender) {}

    /**
     * @dev See {IBlocklockSender-requestBlocklock}.
     */
    function requestBlocklock(uint256 blockHeight, bytes calldata ciphertext)
        external
        returns (uint256 blocklockRequestID)
    {
        require(blockHeight > block.number, "blockHeight must be strictly greater than current");

        blocklockRequestID = ++lastRequestID;
        TypesLib.BlocklockRequest memory r = TypesLib.BlocklockRequest({
            signatureRequestID: 0,
            blockHeight: blockHeight,
            ciphertext: ciphertext,
            signature: hex"",
            callback: msg.sender
        });

        // Try to re-use a previous signature request for this blockHeight
        uint256 previousSignatureRequestID = signatureRequests[blockHeight];
        if (previousSignatureRequestID > 0) {
            // Re-use a previous signature request for the same blockHeight
            r.signatureRequestID = previousSignatureRequestID;
        } else {
            // New signature request
            bytes memory m = abi.encode(blockHeight);
            bytes memory conditions = m;

            uint256 signatureRequestID = signatureSender.requestSignature(SCHEME_ID, m, conditions);
            r.signatureRequestID = signatureRequestID;

            // Store the signature requestID for this blockHeight
            signatureRequests[blockHeight] = signatureRequestID;
        }
        // Store the blocklockRequest in the mapping
        blocklockRequests[blocklockRequestID] = r;
        // Store the blocklockRequestID for the corresponding signature requestID
        signaturesToBlocklock[r.signatureRequestID].push(blocklockRequestID);

        emit BlocklockRequested(
            blocklockRequestID, r.signatureRequestID, blockHeight, ciphertext, msg.sender, block.timestamp
        );
    }

    /**
     * @dev See {SignatureReceiverBase-onSignatureReceived}.
     */
    function onSignatureReceived(uint256 signatureRequestID, bytes calldata signature) internal override {
        uint256[] memory requests = signaturesToBlocklock[signatureRequestID];
        require(requests.length > 0, "invalid signatureRequestID");

        TypesLib.BlocklockRequest memory r;
        for (uint256 i = 0; i < requests.length; ++i) {
            r = blocklockRequests[requests[i]];
            require(r.signatureRequestID > 0, "no matching blocklock request for that id");

            r.signature = signature;

            (bool success,) = r.callback.call(
                abi.encodeWithSelector(IBlocklockReceiver.receiveBlocklock.selector, signatureRequestID, signature)
            );
            if (!success) {
                emit BlocklockCallbackFailed(requests[i], signatureRequestID, r.blockHeight, signature);
            } else {
                emit BlocklockCallbackSuccess(requests[i], signatureRequestID, r.blockHeight, r.ciphertext, signature);
            }
            // todo review - if request callback fails, should it be deleted and treated as fulfilled?
            // caller might not be contract implementing right interface
            // or malicious contract that just reverts
            delete blocklockRequests[requests[i]];
        }

        // Delete from mapping
        signaturesToBlocklock[signatureRequestID];
        signatureRequests[r.blockHeight];
    }

    /**
     * @dev See {ISignatureSender-isInFlight}.
     */
    function isInFlight(uint256 requestID) external view returns (bool) {
        uint256 signatureRequestID = blocklockRequests[requestID].signatureRequestID;
        require(signatureRequestID > 0, "blocklock request not found");

        return signatureSender.isInFlight(signatureRequestID);
    }

    /**
     * @dev See {IBlocklockSender-getRequest}.
     */
    function getRequest(uint256 requestID) external view returns (TypesLib.BlocklockRequest memory) {
        TypesLib.BlocklockRequest memory r = blocklockRequests[requestID];
        require(r.signatureRequestID > 0, "invalid requestID");

        return r;
    }
}
