import { ethers } from 'ethers';
import { SimpleAuction__factory } from "../src/generated"

// Define Types
interface PointG2 {
  x: [bigint, bigint];
  y: [bigint, bigint];
}

interface Ciphertext {
  u: PointG2;
  v: string;
  w: string;
}

interface BidResponse {
  sealedAmount: Ciphertext;
  decryptionKey: string;
  unsealedAmount: bigint;
  bidder: string;
  revealed: boolean;
}

async function getBidDetails(bidID: bigint) {
    const rpc = new ethers.JsonRpcProvider("http://localhost:8545")
const contract = SimpleAuction__factory.connect("0x6dc4c8e8d4369974206e64cfb3a2280e0eff133a", rpc)
  // Call the getBidWithBidID function
  const bidDetails = await contract.getBidWithBidID(bidID);

  // Deconstruct the response into the corresponding types
  const {
    sealedAmount,
    decryptionKey,
    unsealedAmount,
    bidder,
    revealed,
  }: BidResponse = bidDetails;

  // Convert the `bytes` fields to raw bytes if needed
  const decryptionKeyBytes = ethers.hexlify(decryptionKey); // Convert hex to byte array

  // Log the values for inspection
  console.log('Sealed Amount u.x:', sealedAmount.u.x);
  console.log('Sealed Amount u.y:', sealedAmount.u.y);
  console.log('Decryption Key:', decryptionKeyBytes);
  console.log('Unsealed Amount:', unsealedAmount);
  console.log('Bidder Address:', bidder);
  console.log('Revealed:', revealed);
}

// Usage (assuming `contract` is already instantiated with the ABI)
const bidID = BigInt('1'); // Example bidID
getBidDetails(bidID);
