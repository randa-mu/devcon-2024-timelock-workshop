# Developer Workshop: Secure Sealed-Bid Auction with Timelock Encryption


## Prerequisites

Install Foundry, and ensure you have:
* [moon](https://moonrepo.dev/docs/install)
* [npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm) version >= 10.9.0
* [node](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm) version >= 22.3.0
* [yarn](https://classic.yarnpkg.com/lang/en/docs/install/#mac-stable)


## Workshop Steps

### Step 1: Project Setup

1. Navigate to the project root folder:
    ```bash
    cd devcon-2024-timelock-workshop
    ```

2. Run the build command for the project:
   ```bash
   moon run :build
   ```

### Step 2: Start Anvil

1. Start the Anvil local blockchain with the following command:
   ```bash
   chmod +x bls-bn254-js/scripts/anvil-start.sh
   ./bls-bn254-js/scripts/anvil-start.sh
   ```

### Step 3: Start Timelock Agent
The timelock agent deploys the necessary smart contracts to the Anvil network, monitors timelock encryption request events from these contracts, and fulfills requests by generating signatures over the ciphertexts in each request at a specified block number. These signatures, which serve as decryption keys for the ciphertexts, remain unknown until the designated block number is reached. This process establishes the core functionality of timelock encryption.

1. Start the timelock agent in a new console window, separate from the Anvil window:
   ```bash
   cd blocklock-agent && npm run start
   ```

### Step 4: Configure and Deploy Auction Contract

1. Note the **Simple Auction Contract Deployment Parameters**:
   - Contract Address: `0x78e6B135B2A7f63b281C80e2ff639Eed32E2a81b`
   - Configuration:
     - Duration (blocks): `50`
     - End Block Number: `56`
     - Reserve Price: `0.1 ETH`
     - Bid Fulfillment Window (post-auction, blocks): `5`
   - Timelock Writer: running on `port 8080`

### Step 5: Encrypt Bids for Sealed-Bid Auction

1. **Encrypt the bid amount for Bidder A (0.3 ETH)**:
   ```bash
   cast to-wei 0.3   # Result: 300000000000000000
   cd bls-bn254-js
   yarn ibe:encrypt --message 300000000000000000 --blocknumber 56
   ```
   - This will generate the ciphertext to use for Bidder A’s sealed bid.

2. **Encrypt the bid amount for Bidder B (0.4 ETH)**:
   ```bash
   yarn ibe:encrypt --message 400000000000000000 --blocknumber 56
   ```
   - This generates the ciphertext for Bidder B, making Bidder B the highest bidder.

### Step 6: Submit Sealed Bids to the Auction Contract

1. **Bidder A submits sealed bid (0.3 ETH)**:
   ```bash
   cast send 0x78e6B135B2A7f63b281C80e2ff639Eed32E2a81b "sealedBid(bytes)" \
   <Ciphertext from Step 5 for Bidder A> \
   --value 0.1ether \
   --private-key 0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e
   ```

2. **Bidder B submits sealed bid (0.4 ETH)**:
   ```bash
   cast send 0x78e6B135B2A7f63b281C80e2ff639Eed32E2a81b "sealedBid(bytes)" \
   <Ciphertext from Step 5 for Bidder B> \
   --value 0.1ether \
   --private-key 0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97
   ```

### Step 7: Verify Submitted Sealed Bids

1. Check the latest block number:
   ```bash
   cast block-number
   ```
2. **View Sealed Bids**:
   - For **Bidder A**:
     ```bash
     cast call 0x78e6B135B2A7f63b281C80e2ff639Eed32E2a81b "getBidWithBidID(uint256)" 1
     ```
   - Decode the returned bytes to view the bid data.
   ```
   cast abi-decode "getBidWithBidID(uint256)(bytes,bytes,uint256,address,bool)" <place output from command above here>
   ```

### Step 8: Skip to Auction End Block

1. Run the following script to skip blocks to the auction end:
   ```bash
   chmod +x bls-bn254-js/scripts/anvil-skip-to-block.sh
   ./bls-bn254-js/scripts/anvil-skip-to-block.sh 56
   ```

2. **Verify Fulfilled Timelock Requests**:
   - You should see the logs in the agent console showing that the agent has now signed the ciphertexts from the two earlier sealed bid events:
     ```
     fulfilling signature request 1
     fulfilled signature request
     ```

### Step 9: End the Auction

1. Use the deployer private key to end the auction:
   ```bash
   cast send 0x78e6B135B2A7f63b281C80e2ff639Eed32E2a81b "endAuction()" \
   --private-key 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
   ```

### Step 10: Reveal Bids and Verify Data

1. **View Revealed Bid Data**:
   - Retrieve and decode data for Bidder A to confirm `revealed` status and `unsealedAmount`:
     ```bash
     cast call 0x78e6B135B2A7f63b281C80e2ff639Eed32E2a81b "getBidWithBidID(uint256)" 1
     ```

2. **Decrypt Bid Amount Using Signature**:
   ```bash
   yarn ibe:decrypt --ciphertext <ciphertext> --signature <signature>
   ```

3. **Convert Decrypted Value to Ether**:
   ```bash
   cast from-wei 300000000000000000
   ```

4. **Reveal Bid Amounts with Auctioneer Key**:
   - For **Bidder A**:
     ```bash
     cast send 0x78e6B135B2A7f63b281C80e2ff639Eed32E2a81b "revealBid(uint256,uint256)" \
     1 \
     300000000000000000 \
     --private-key 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
     ```
   - For **Bidder B**:
     ```bash
     cast send 0x78e6B135B2A7f63b281C80e2ff639Eed32E2a81b "revealBid(uint256,uint256)" \
     2 \
     400000000000000000 \
     --private-key 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
     ```
