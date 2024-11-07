# Developer Workshop: Secure Sealed-Bid Auction with Timelock Encryption




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
   npm run start:anvil
   ```

### Step 3: Start Timelock Agent
The timelock agent deploys the necessary smart contracts to the Anvil network, monitors timelock encryption request events from these contracts, and fulfills requests by generating signatures over the ciphertexts in each request at a specified block number. These signatures, which serve as decryption keys for the ciphertexts, remain unknown until the designated block number is reached. This process establishes the core functionality of timelock encryption.

1. Start the timelock agent in a new terminal window, separate from the Anvil window:
   ```bash
   npm run start:timelock-agent
   ```
   **Note**: If you get any `nonce` related errors, restart the Anvil local blockchain and retry starting the agent.

   Upon deployment of the smart contracts, you will notice the following deployment deployment configurations for the Simple Auction smart contract as part of the logs in the timelock agent console:
   - Contract Address: `0xa945472E43646254913578f0dc0adb0c73a5F584`
   - Configuration:
     - Auction Duration (blocks): `50`
     - Auction End Block Number: `56`
     - Auction Reserve Price: `0.1 ETH`
     - Bid Fulfillment Window (post-auction, blocks): `10` // The highest bid can be fulfilled by the highest bidder after the auction end block and up until block 66 (end block 56 + 10 additional blocks).

We will run the next set of tasks in another terminal window.

### Step 4: Encrypt Bids for Sealed-Bid Auction

1. **Encrypt the bid amount for Bidder A (0.3 ETH)**:
   ```bash
   cast to-wei 0.3   # Result: 300000000000000000
   npm run timelock:encrypt -- --message=300000000000000000 --blocknumber=56
   ```
   - This will generate the ciphertext to use for Bidder A’s sealed bid with the auction ending block number to ensure that the bid amount can only be decrypted once this block has been mined. Please make note of it.

2. **Encrypt the bid amount for Bidder B (0.4 ETH)**:
   ```bash
   cast to-wei 0.4   # Result: 400000000000000000
   npm run timelock:encrypt -- --message=400000000000000000 --blocknumber=56
   ```
   - This generates the ciphertext for Bidder B's bid amount of 0.4 ether, making Bidder B the highest bidder. Please make note of it.

### Step 5: Submit Sealed Bids to the Auction Contract

1. **Bidder A submits sealed bid (0.3 ETH)**:
   ```bash
   cast send 0xa945472E43646254913578f0dc0adb0c73a5F584 "sealedBid(bytes)" \
   <replace this with the Ciphertext from Step 4 for Bidder A> \
   --value 0.1ether \
   --private-key 0xe46f7a0c8e6110e8386242cad3491bd38fb794a28dfa751e826a03c8818fe282
   ```

2. **Bidder B submits sealed bid (0.4 ETH)**:
   ```bash
   cast send 0xa945472E43646254913578f0dc0adb0c73a5F584 "sealedBid(bytes)" \
   <replace this with the Ciphertext from Step 4 for Bidder B> \
   --value 0.1ether \
   --private-key 0xd4153f5547461a9f34a6da4de803c651c19794f62375d559a888b0d7aac38b63
   ```

We can also check the wallet addresses for bidder A and B using the following command with their private keys:
```bash
cast wallet address --private-key <replace this with the private key to convert to a wallet address>
```

e.g., for bidder A:
```bash
cast wallet address --private-key 0xe46f7a0c8e6110e8386242cad3491bd38fb794a28dfa751e826a03c8818fe282
```


### Step 6: Verify Submitted Sealed Bids

1. **View Sealed Bids**:
   - For **Bidder A** with bidID 1:
     ```bash
     cast call 0xa945472E43646254913578f0dc0adb0c73a5F584 "getBidWithBidID(uint256)" 1
     ```
   - Decode the returned bytes to view the bid data.
   ```
   cast abi-decode "getBidWithBidID(uint256)(bytes,bytes,uint256,address,bool)" <place output from command above here>
   ```
   This should return five outputs on separate lines. These are:
      * `bytes sealedAmount` - the ciphertext representing the (timelock encrypted) sealed bid.
      * `bytes decryptionKey` - the decryption key used to decrypt the sealedAmount.
      * `uint256 unsealedAmount` - the unsealed bid amount.
      * `address bidder` - the wallet address of the bidder.
      * `bool revealed` - a boolean true or false indicating whether the bid has been unsealed or not.

   Based on the output for the decryptionKey being `0x`, we can see that the timelock agent has not yet passed the decryption key back to the smart contract. This is because the block number for decryption (auction ending block number `56`) has not reached.
   
   We can repeat the step above to get the current on-chain bid data for **Bidder B** but changing the bidID to 2, i.e., 
   ```bash
   cast call 0xa945472E43646254913578f0dc0adb0c73a5F584 "getBidWithBidID(uint256)" 2
   ```

### Step 7: Skip to Auction End Block

As per the above outputs, the smart contract has not received any decryption keys for the sealed bids. This is because the bids were encrypted with the auction ending block number which is `56` as in Step 3 and this block number has not reached or been mined on the local Anvil blockchain. Therefore, without the decryption keys, none of the bids can be unsealed by the auctioneer. 

1. Check the current block number:
   ```bash
   cast block-number
   ```

   The current block number is still less than the auction ending block number which is `56` from Step 3. Since we are on a local blockchain, we can mine the number of blocks between the current block number and our target block number to skip to the auction ending block number. 

2. Run the following to skip blocks to the block after the auction end (block number `57):
   ```bash
   npm run skip:to-block 57
   ```

3. **Verify Fulfilled Timelock Requests**:
   - You should see a new transaction being sent at block `58` in the Anvil blockchain logs as well as the following logs in the timelock agent console showing that the timelock encryption agent has now signed the ciphertexts from the two earlier sealed bid events and sent the decryption key to the `SignatureSender` smart contract which forwards the signature to the `SimpleAuction` smart contract via the `BlocklockSender` contract:
     ```
     fulfilling signature request 1
     fulfilled signature request
     ```

### Step 8: End the Auction

1. Use the deployer (auctioneer) private key to end the auction:
   ```bash
   cast send 0xa945472E43646254913578f0dc0adb0c73a5F584 "endAuction()" \
   --private-key 0xecc372f7755258d11d6ecce8955e9185f770cc6d9cff145cca753886e1ca9e46
   ```

### Step 9: Reveal Bids and Verify Data

1. **View Bid Data and Get Decryption Key**:
   - Retrieve and decode data for Bidder A to view the `decryptionKey` and check the `revealed` status and `unsealedAmount`:
     ```bash
     cast call 0xa945472E43646254913578f0dc0adb0c73a5F584 "getBidWithBidID(uint256)" 1
     ```

   - Decode the returned bytes to view the bid data.
   ```
   cast abi-decode "getBidWithBidID(uint256)(bytes,bytes,uint256,address,bool)" <place output from command above here>
   ```
   This should return five outputs on separate lines. These are:
      * `bytes sealedAmount` - the ciphertext representing the (timelock encrypted) sealed bid.
      * `bytes decryptionKey` - the decryption key used to decrypt the sealedAmount.
      * `uint256 unsealedAmount` - the unsealed bid amount.
      * `address bidder` - the wallet address of the bidder.
      * `bool revealed` - a boolean true or false indicating whether the bid has been unsealed or not.

   We can now see that the decryptionKey has been sent to the auction smart contract after the auction end block number was identified by the timelock agent. The decryptionKey is no longer an empty byte string `0x`. Using the ciphertext and decryption key from the output above, we can decrypt the sealed bid to reveal the bid amount and confirm that the amount is the same as the amounts we encrypted to ciphertexts earlier for each bidder - Bidder A and Bidder B.

2. **Decrypt Bid Amounts Using Decryption Keys (Signature over Ciphertext)**:
   ```bash
   npm run timelock:decrypt -- --ciphertext <replace with ciphertext from decoded output> --signature <replace with signature or decryption key from decoded output>
   ```

   For example, if the output from the decode step is as follows:
   ```bash
   0x3081c530818c304402200eed73a85cc36f2a5db49aa51ff569719f7c121288fb0ce0e5fad0e0089a7761022011d784a04eb5a5f225eb67db8cefa103920d3cc6bfab06ac4bafd753fcf2dd613044022021ac63607b8e90518db9e3f0f14c32650275904a374ce0c8cbdca8468fd77aaa0220224478938ae7511a30211f7d6c1fb216dafdf507d89a763303c36932a4f22a2d0420ff7b5124b22ffbaae6ae25bd03bc1d86b0bb8bebb2326005085ff9c4d2d01468041284378407738c7564d6c2422d542d8b0d690e
   0x2378d9fcdcaf7c6471cef67e6108463c8ab8ee60cf7774625321569ada5eddff232cced183a044890ef628fd529ec5a1d44a37b0f24fa4dbea6a5a1c236f9ec4
   0
   0x2A4F2CcE249A47edE31f091e521625c6879bd4a7
   false
   ```

   We can decrypt as follows:
   ```bash
   npm run timelock:decrypt -- --ciphertext 0x3081c530818c304402200eed73a85cc36f2a5db49aa51ff569719f7c121288fb0ce0e5fad0e0089a7761022011d784a04eb5a5f225eb67db8cefa103920d3cc6bfab06ac4bafd753fcf2dd613044022021ac63607b8e90518db9e3f0f14c32650275904a374ce0c8cbdca8468fd77aaa0220224478938ae7511a30211f7d6c1fb216dafdf507d89a763303c36932a4f22a2d0420ff7b5124b22ffbaae6ae25bd03bc1d86b0bb8bebb2326005085ff9c4d2d01468041284378407738c7564d6c2422d542d8b0d690e --signature 0x2378d9fcdcaf7c6471cef67e6108463c8ab8ee60cf7774625321569ada5eddff232cced183a044890ef628fd529ec5a1d44a37b0f24fa4dbea6a5a1c236f9ec4
   ```

   When we decrypt the sealed bid for Bidder A with Bid ID 1 we should see the following decrypted data in the console:
   ```bash
   Decrypted message as hex: 0x333030303030303030303030303030303030
   Decrypted message as plaintext string: 300000000000000000
   ```

   We can repeat the same steps for Bidder B's sealed bid.

3. **Convert Decrypted Value from Wei to Ether**:
   If we convert the decrypted value from wei to ether, we should get 0.3 ether which we encrypted as wei earlier for Bidder A in Step 4.
   ```bash
   cast from-wei 300000000000000000
   ```
   We can repeat the decryption steps for Bidder B and confirm the decrypted amount.

4. **Reveal Bid Amounts on-chain with Auctioneer Key**:
   Now the auctioneer can reveal the bid amounts in the smart contract and with the decryption keys, anyone can verify the revealed amounts are correct with the decryption keys which have only been made available after the auction ending block number.

   Reveal bid amounts -
   - For **Bidder A**:
     ```bash
     cast send 0xa945472E43646254913578f0dc0adb0c73a5F584 "revealBid(uint256,uint256)" \
     1 \
     300000000000000000 \
     --private-key 0xecc372f7755258d11d6ecce8955e9185f770cc6d9cff145cca753886e1ca9e46
     ```
   - For **Bidder B**:
     ```bash
     cast send 0xa945472E43646254913578f0dc0adb0c73a5F584 "revealBid(uint256,uint256)" \
     2 \
     400000000000000000 \
     --private-key 0xecc372f7755258d11d6ecce8955e9185f770cc6d9cff145cca753886e1ca9e46
     ```

5. **View Revealed Bid Data**:
   - Retrieve and decode data for Bidder A to confirm `revealed` status and `unsealedAmount`:
     ```bash
     cast call 0xa945472E43646254913578f0dc0adb0c73a5F584 "getBidWithBidID(uint256)" 1
     ```

   - Decode the returned bytes to view the bid data.
   ```
   cast abi-decode "getBidWithBidID(uint256)(bytes,bytes,uint256,address,bool)" <place output from command above here>
   ```
   This should return five outputs on separate lines. These are:
      * `bytes sealedAmount` - the ciphertext representing the (timelock encrypted) sealed bid.
      * `bytes decryptionKey` - the decryption key used to decrypt the sealedAmount.
      * `uint256 unsealedAmount` - the unsealed bid amount.
      * `address bidder` - the wallet address of the bidder.
      * `bool revealed` - a boolean true or false indicating whether the bid has been unsealed or not.

   We can now see that the `unsealedAmount` is the amount in Wei that was encrypted in Step 4 and the `revealed` flag in the bid data has now been set to `true` for both bidders.

6. **View Highest Bid Amount and Highest Bidder Address**:
   ```bash
   cast call 0xa945472E43646254913578f0dc0adb0c73a5F584 "getHighestBid()" 
   ```

   Decode the output from the above command:
   ```
   cast abi-decode "getHighestBid()(uint256)" <place output from command above here>
   ```
   Upon decoding the output for the highest bid after revealing both sealed bids, we can see that the highest bid is `400000000000000000` or `0.4 ether` which is the bid amount for Bidder B.

   Next, let us get the address of the highest bidder from the auction smart contract:
   ```bash
   cast call 0xa945472E43646254913578f0dc0adb0c73a5F584 "getHighestBidder()" 
   ```

   Decode the output from the above command:
   ```
   cast abi-decode "getHighestBidder()(address)" <place output from command above here>
   ```

   We can confirm that the highest bidder address is bidder B's address using B's private key from Step 5:
   ```bash
   cast wallet address --private-key 0xd4153f5547461a9f34a6da4de803c651c19794f62375d559a888b0d7aac38b63
   ```

### Step 10: Optional extra tasks to finalise the auction process.

1. **Fulfil Highest Bid**:
   To finish off the auction process, bidder B can fulfil the highest bid by paying 0.3 ether which is the difference between the highest bid amount of 0.4 ether and the reserve price of 0.1 ether paid by all bidders during the sealed bid transaction.
   ```bash
   cast send 0xa945472E43646254913578f0dc0adb0c73a5F584 "fulfilHighestBid()" \
   --value 0.3ether \
   --private-key 0xd4153f5547461a9f34a6da4de803c651c19794f62375d559a888b0d7aac38b63 
   ```

2. **Withdraw paid reserve price**
   The non-winning bidder, bidder A can also withdraw the reserve price of 0.1 ether paid as part of the sealed bid transaction.
   ```bash
   cast send 0xa945472E43646254913578f0dc0adb0c73a5F584 "withdrawDeposit()" \
   --private-key 0xe46f7a0c8e6110e8386242cad3491bd38fb794a28dfa751e826a03c8818fe282 
   ```