// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title TypesLib
/// @notice Library containing types used for secure, blockchain-related requests.
/// @dev Provides definitions for request structures used in cryptographic operations,
///      including block-locked requests and signature requests.
library TypesLib {
    /// @notice Struct to represent a block-locked decryption request.
    /// @dev This struct holds information necessary for generating decryption keys
    ///      tied to a specific block height.
    struct BlocklockRequest {
        /// @notice Unique identifier for the signature request.
        uint256 signatureRequestID;
        /// @notice The specific block height at which the decryption operation is intended.
        /// @dev Provides temporal context to ensure that the request is only signed at or after
        ///      the specified block height.
        uint256 blockHeight;
        /// @notice Encrypted data payload associated with the request.
        /// @dev The ciphertext is securely processed, ensuring that data remains private
        ///      until the intended decryption conditions are met.
        bytes ciphertext;
        /// @notice Digital signature validating the authenticity of the request.
        /// @dev Used to confirm the origin and integrity of the `BlocklockRequest`.
        bytes signature;
        /// @notice Callback address to notify the requester upon completion.
        /// @dev The contract at this address should implement the expected callback functionality
        ///      for receiving the outcome of the request.
        address callback;
    }

    /// @notice Struct to represent a request for message signing.
    /// @dev Holds all details necessary to sign a message under specified conditions.
    struct SignatureRequest {
        /// @notice Plaintext message intended for hashing and signing.
        bytes message;
        /// @notice Hash of the `message` that will be signed.
        /// @dev Hashing ensures consistency and provides a fixed-size input for signing.
        bytes messageHash;
        /// @notice Optional condition for signing the message.
        /// @dev If this field is empty, the request implies immediate signing.
        ///      If non-empty, additional logic may be required to verify the condition.
        bytes condition;
        /// @notice Identifier for the signature scheme to be used, e.g., "BN254", "BLS12-381", "TESS".
        /// @dev This scheme ID determines the cryptographic signing protocol applied to the message.
        string schemeID;
        /// @notice Callback address of the requester to notify upon signing completion.
        /// @dev This address must implement the `ISignatureReceiver` interface for handling
        ///      the callback, ensuring compatibility with the expected signing result.
        address callback;
    }
}
