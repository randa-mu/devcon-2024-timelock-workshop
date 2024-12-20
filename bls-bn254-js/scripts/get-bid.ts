import { ethers } from 'ethers';
import { SimpleAuction__factory } from "../src/generated"
import { Command, Option } from 'commander'

// Define the CLI command and arguments using `commander`
const program = new Command()

const defaultRPC = "http://localhost:8545"

program
  .addOption(new Option("--rpc-url <rpc-url>", "The websockets/HTTP URL to connect to the blockchain from")
    .default(defaultRPC)
  )
  .requiredOption('--contractAddr <contractAddr>', 'Deployed auction smart contract address required to blockchain network')
  .requiredOption('--bidId <bid id>', 'Identifier assigned to the bid')

program.parse(process.argv)

// Extract parsed options
const options = program.opts()
const rpcAddr: string = options.rpcURL
const contractAddr: string = options.contractAddr
const bidId: string = options.bidId

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
const rpc = new ethers.JsonRpcProvider(rpcAddr)

const contract = SimpleAuction__factory.connect(contractAddr, rpc)
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
  console.log('Sealed Amount:', {
    U: {x: sealedAmount.u.x, y: sealedAmount.u.y},
    V: sealedAmount.v,
    W: sealedAmount.w
  });
  console.log('Decryption Key:', decryptionKeyBytes);
  console.log('Unsealed Amount:', unsealedAmount);
  console.log('Bidder Address:', bidder);
  console.log('Revealed:', revealed);
}

// Usage (assuming `contract` is already instantiated with the ABI)
const bidID = BigInt(bidId); // Example bidID
getBidDetails(bidID);
