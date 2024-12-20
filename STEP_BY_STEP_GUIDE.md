# Developer Workshop: Secure Sealed-Bid Auction with Timelock Encryption

In this workshop, we are working with a **Simple Auction Smart Contract** that utilizes **sealed bids** and **timelock encryption** for enhanced security and privacy.

#### Key Concepts:

- **Sealed Bids**: Bidders submit their offers in a "sealed" manner, meaning the bid amount is hidden until the auction ends. This ensures that participants cannot alter their bids based on others' offers, maintaining fairness.

- **Timelock Encryption**: To ensure the confidentiality of the bids, they are secured with **timelock encryption**. This encryption scheme ensures that the bid remains confidential until a specified block number, preventing any unauthorized access or manipulation before that time.

#### How it works:

1. **Bid Submission**: Participants submit their bids, which are encrypted using a **timelock encryption scheme** (based on the BLS-BN254 curve). The encryption ensures that the correct bid is revealed at a time in the future.

2. **Auction Duration**: The auction runs for a set number of blocks (e.g., 50 blocks). During this period, participants cannot view or change their bids.

3. **End of Auction**: Once the auction period ends or the auction end block is mined, the smart contract receives the decryption keys for each bid which can then be used to reveal the highest bid and the winning participant. The decryption happens fully on-chain.

4. **Signature Verification**: The system uses **BLS-BN254 signatures** for validating and revealing bids securely. The smart contract verifies the signatures to ensure that the correct bids are revealed after the timelock condition is satisfied.

#### Advantages:
- **Fairness**: No participant can alter their bid based on others’ offers.
- **Security**: The use of BLS signatures and timelock encryption prevents unauthorized tampering or early revelation of bids.
- **Confidentiality**: Bids are hidden until the auction concludes, ensuring privacy for all participants.

This approach offers a technique for implementing privacy-preserving auctions in a decentralized environment, leveraging cryptographic techniques to ensure security and fairness.



### Step 1: Docker services overview 

The following services are defined within the `docker-compose.yml` file:

* **anvil**: runs a local Anvil. Anvil is a fast and lightweight Ethereum-compatible blockchain client designed to help developers run their own local Ethereum network. It is primarily used in development environments to simulate an Ethereum-like blockchain for testing smart contracts and decentralized applications (dApps) without having to interact with the main Ethereum network or testnets.

* **blocklock**: runs a timelock agent which deploys the necessary smart contracts to the Anvil network, monitors timelock encryption request events from these contracts, and fulfills requests by generating signatures over the ciphertexts in each request at a specified block number. These signatures, which serve as decryption keys for the ciphertexts, remain unknown until the designated block number is reached. This process establishes the core functionality of timelock encryption.

* **bls-bn254-js**: is used to generate Ciphertexts and submit bids to the smart contract by the timelock agent. We will also use this container to interact with the smart contracts deployed on Anvil, e.g., to fetch and view submitted bid data, highest bid amount and highest bidder at the end of the auction period.

Firstly, we need to deploy the factory smart contract. This contract serves as a deployer for the rest of the smart contracts. 

Let's open an interactive bash shell or terminal window in the container named `bls-bn254-js-container`. We will run the rest of the commands from this container:
```bash
docker exec -it bls-bn254-js-container bash
```

The run the following command to deploy the factory contract:
```bash
cd .. && forge create smart-contracts/src/deployer/Deployer.sol:Deployer --private-key 0xe46f7a0c8e6110e8386242cad3491bd38fb794a28dfa751e826a03c8818fe282 --rpc-url $RPC_URL && exit
```

Let us check that the rest of the contracts are deployed via the factory contract by running the following command: 
```bash
docker compose logs blocklock
```

At the end of the smart contract deployment process, we will see the following deployment configurations for the Simple Auction smart contract as part of the logs in the timelock agent console:
   - auction contract deployed to `0x7eeeb0bd9d94d989b956052ebf8a351c52949a0d`
   - auction end block `57`

We can also check the logs for the other services, e.g., `anvil`, by running the following command, 
```bash
docker compose logs anvil
```

and `bls-bn254-js`, by running the following command, 
```bash
docker compose logs bls-bn254-js
```


### Step 2: Encrypt and place bids for sealed-bid auction

Let's return to our `bls-bns245-js` interactive terminal window:

```bash
docker exec -it bls-bn254-js-container bash
```

1. **Encrypt and place a bid for Bidder A (3 ETH)**:
   ```bash
   npm run timelock:encrypt-and-bid -- --message 3 --blocknumber 57 --rpc-url $RPC_URL --privateKey 0xd4153f5547461a9f34a6da4de803c651c19794f62375d559a888b0d7aac38b63 --contractAddr 0x7eeeb0bd9d94d989b956052ebf8a351c52949a0d
   ```
   - This will generate the ciphertext to use for Bidder A’s sealed bid with the auction ending block number to ensure that the bid amount can only be decrypted once this block has been mined. Please make note of it.

   We can confuirm the bid in Wei using the following command:
   ```bash
   cast to-wei 3   # Result: 3000000000000000000
   ```

2. **Encrypt and place a bid for Bidder B (4 ETH)**:
   ```bash
   npm run timelock:encrypt-and-bid -- --message 4 --blocknumber 57 --rpc-url $RPC_URL --privateKey 0x36fba493641ed3b3272d62025652558120c372e26c6ae38f403549508da81ec9 --contractAddr 0x7eeeb0bd9d94d989b956052ebf8a351c52949a0d
   ```
   - This generates the ciphertext for Bidder B's bid amount of 4 ether, making Bidder B the highest bidder. Please make note of it.

### Step 3: Verify submitted sealed bids

1. **View sealed bids**:
   - For **Bidder A** with bidID 1:
     ```bash
     npm run timelock:get-bid -- --contractAddr  0x7eeeb0bd9d94d989b956052ebf8a351c52949a0d --bidId 1
     ```
   
   Based on the output for the decryptionKey being `0x`, we can see that the timelock agent has not yet passed the decryption key back to the smart contract. This is because the block number for decryption (auction ending block number `57`) has not reached.
   
   We can repeat the step above to get the current on-chain bid data for **Bidder B** but changing the bidID to 2, i.e., 
   ```bash
   npm run timelock:get-bid -- --contractAddr  0x7eeeb0bd9d94d989b956052ebf8a351c52949a0d --bidId 2
   ```

### Step 4: Skip to blocks to end the auction

As per the above outputs, the smart contract has not received any decryption keys for the sealed bids. This is because the bids were encrypted with the auction ending block number which is `57` as in Step 1 and this block number has not reached or been mined on the local Anvil blockchain. Therefore, without the decryption keys, none of the bids can be unsealed by the auctioneer. 

1. Check the current block number:
   ```bash
   cast block-number --rpc-url $RPC_URL
   ```

   The current block number is still less than the auction ending block number which is `57` from Step 3. Since we are on a local blockchain, we can mine the number of blocks between the current block number and our target block number to skip to the auction ending block number. 

2. Run the following command to skip blocks to the auction ending block number (block number `57):
   ```bash
   npm run skip:to-block 57 $RPC_URL && exit
   ```

3. **Verify fulfilled timelock requests**:
When we check the logs for the timelock service:
```bash
docker compose logs blocklock
```
we should see a new transaction being sent at block `58` in the Anvil blockchain logs as well as the following logs in the timelock agent console showing that the timelock encryption agent has now signed the Ciphertexts from the two earlier sealed bid events and sent the decryption key to the `SignatureSender` smart contract which forwards the signature to the `SimpleAuction` smart contract via the `BlocklockSender` contract:
     ```
     creating a timelock signature for block 57
     fulfilling signature request 1
     fulfilling signature request 2
     fulfilled signature request
     fulfilled signature request
     ```

The transaction sent will also update the auction state to `Ended` to end the auction on-chain.

### Step 5: Reveal bids and verify data

Let's return to our `bls-bns245-js` interactive terminal window:

```bash
docker exec -it bls-bn254-js-container bash
```

1. **View bid data with decryption key**:
   - Retrieve and decode data for Bidder A to view the `decryptionKey` and check the `revealed` status and `unsealedAmount`:
     ```bash
     npm run timelock:get-bid -- --contractAddr  0x7eeeb0bd9d94d989b956052ebf8a351c52949a0d --bidId 1
     ```

   This should return five outputs on separate lines. These are:
      * `bytes sealedAmount` - the ciphertext representing the (timelock encrypted) sealed bid.
      * `bytes decryptionKey` - the decryption key used to decrypt the sealedAmount.
      * `uint256 unsealedAmount` - the unsealed bid amount.
      * `address bidder` - the wallet address of the bidder.
      * `bool revealed` - a boolean true or false indicating whether the bid has been unsealed or not.

   We can now see that the decryptionKey has been sent to the auction smart contract after the auction end block number was identified by the timelock agent. The decryptionKey is no longer an empty byte string `0x`. Using the ciphertext and decryption key from the output above, we can decrypt the sealed bid on-chain to reveal the bid amount and confirm that the amount is the same as the amounts we encrypted to ciphertexts earlier for each bidder - Bidder A and Bidder B.

2. **Decrypt bid amounts with decryption keys (i.e., signature over the Ciphertext)**:

   Firstly, for Bidder A with bid Id 1:
   ```bash
   cast send 0x7eeeb0bd9d94d989b956052ebf8a351c52949a0d "revealBid(uint256)" 1 --private-key 0xd4153f5547461a9f34a6da4de803c651c19794f62375d559a888b0d7aac38b63 --rpc-url $RPC_URL
   ```

   When we decrypt the sealed bid for Bidder A with Bid ID 1 we should now see the unsealed bid amount in plaintext when we fetch the associated bid data again:
   ```bash
   npm run timelock:get-bid -- --contractAddr  0x7eeeb0bd9d94d989b956052ebf8a351c52949a0d --bidId 1
   ```

   If we convert the decrypted value from wei to ether for Bidder A, we should get 3 ether which we encrypted as wei earlier for Bidder A in Step 2.
   ```bash
   cast from-wei 3000000000000000000
   ```

   We can repeat the same steps for Bidder B's sealed bid with bid Id 2 and Bidder B's private key (*note that anyone can call the reveal bid function as the decryption key is now on-chain*).

   ```bash
   cast send 0x7eeeb0bd9d94d989b956052ebf8a351c52949a0d "revealBid(uint256)" 2 --private-key 0x36fba493641ed3b3272d62025652558120c372e26c6ae38f403549508da81ec9 --rpc-url $RPC_URL
   ```

   When we decrypt the sealed bid for Bidder B with Bid ID 2 we should now see the unsealed bid amount in plaintext when we fetch the associated bid data again:
   ```bash
   npm run timelock:get-bid -- --contractAddr  0x7eeeb0bd9d94d989b956052ebf8a351c52949a0d --bidId 2
   ```

   Convert decrypted bid amount from wei to ether:
   ```bash
   cast from-wei 4000000000000000000
   ```

3. **View highest bid amount and highest Bidder Address**:
   ```bash
   cast call 0x7eeeb0bd9d94d989b956052ebf8a351c52949a0d "getHighestBid()" --rpc-url $RPC_URL
   ```

   Decode the output from the above command:
   ```
   cast abi-decode "getHighestBid()(uint256)" <place output from command above here>
   ```
   Upon decoding the output for the highest bid after revealing both sealed bids, we can see that the highest bid is `4000000000000000000` or `4 ether` which is the bid amount for Bidder B.

   Next, let us get the address of the highest bidder from the auction smart contract:
   ```bash
   cast call 0x7eeeb0bd9d94d989b956052ebf8a351c52949a0d "getHighestBidder()" --rpc-url $RPC_URL
   ```

   Decode the output from the above command:
   ```
   cast abi-decode "getHighestBidder()(address)" <place output from command above here>
   ```

   We can confirm that the highest Bidder address is Bidder B's address using B's private key from Step 5:
   ```bash
   cast wallet address --private-key 0x36fba493641ed3b3272d62025652558120c372e26c6ae38f403549508da81ec9
   ```

### Step 6: Optional extra tasks to finalise the auction process.

1. **Fulfil highest bid**:
   To finish off the auction process, Bidder B can fulfil the highest bid by paying 3 ether which is the difference between the highest bid amount of 4 ether and the reserve price of 0.1 ether paid by all bidders during the sealed bid transaction.
   ```bash
   cast send 0xa945472E43646254913578f0dc0adb0c73a5F584 "fulfilHighestBid()" \
   --value 3.9ether \
   --private-key 0x36fba493641ed3b3272d62025652558120c372e26c6ae38f403549508da81ec9 \
   --rpc-url $RPC_URL 
   ```

2. **Withdraw paid reserve price**
   The non-winning bidder, Bidder A can also withdraw the reserve price of 0.1 ether paid as part of the sealed bid transaction.
   ```bash
   cast send 0xa945472E43646254913578f0dc0adb0c73a5F584 "withdrawDeposit()" \
   --private-key 0xd4153f5547461a9f34a6da4de803c651c19794f62375d559a888b0d7aac38b63 \
   --rpc-url $RPC_URL 
   ```

### Step 7: Tidying up
We can exit the terminal window running within the `bls-bn254-js` container, with the following commans:
```bash
exit
```

We can also stop all the running services / containers from the project root folder:
```bash
docker compose down
```
This command will:
   * Stop and remove all containers.
   * Remove networks and volumes (if configured).
   * Retain the images and other build artifacts for future use.

and bring the servies back up again if needed:
```bash
docker compose up -d
```
