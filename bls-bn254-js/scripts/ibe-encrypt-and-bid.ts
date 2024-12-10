import { ethers, AbiCoder, getBytes, Interface, EventFragment, TransactionReceipt, Result } from 'ethers'
import { encrypt_towards_identity_g1, IbeOpts, G2, Ciphertext } from '../src'
import { Command } from 'commander'
import { keccak_256 } from "@noble/hashes/sha3"
import {SimpleAuction__factory} from "../src/generated"
import {TypesLib as BlocklockTypes} from "../src/generated/BlocklockSender"

// Encrypt message with Identity-based Encryption (IBE)
//
// Usage
//  yarn timelock:encrypt-and-bid --message "plaintext message to timelock encrypt, i.e., bid amount" --blocknumber "block number when message can be decrypted"
// yarn timelock:encrypt-and-bid --message 3 --blocknumber 57 --rpcURL http://localhost:8545 --privateKey 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --contractAddr 0x9ffbd8531ac770df4ed8fcd02d76d328ee6cad91

// Define the CLI command and arguments using `commander`
const program = new Command()

program
    .requiredOption('--message <message>', 'Message to be encrypted')
    .requiredOption('--blocknumber <blocknumber>', 'Block number when message can be decrypted')
    .requiredOption('--rpcURL <rpcURL>', 'RPC url used to connect to blockchain network')
    .requiredOption('--privateKey <privateKey>', 'Private key used to send transaction as required to blockchain network')
    .requiredOption('--contractAddr <contractAddr>', 'Deployed auction smart contract address required to blockchain network')

program.parse(process.argv)

// Extract parsed options
const options = program.opts()
const message: string = options.message
const blocknumber: string = options.blocknumber
const rpcAddr: string = options.rpcURL
const privateKey: string = options.privateKey
const contractAddr: string = options.contractAddr

const BLOCKLOCK_DEFAULT_PUBLIC_KEY = {
    x: {
        c0: BigInt("0x2691d39ecc380bfa873911a0b848c77556ee948fb8ab649137d3d3e78153f6ca"),
        c1: BigInt("0x2863e20a5125b098108a5061b31f405e16a069e9ebff60022f57f4c4fd0237bf"),
    },
    y: {
        c0: BigInt("0x193513dbe180d700b189c529754f650b7b7882122c8a1e242a938d23ea9f765c"),
        c1: BigInt("0x11c939ea560caf31f552c9c4879b15865d38ba1dfb0f7a7d2ac46a4f0cae25ba"),
    },
}

const BLOCKLOCK_IBE_OPTS: IbeOpts = {
    hash: keccak_256,
    k: 128,
    expand_fn: "xmd",
    dsts: {
        H1_G1: Buffer.from('BLOCKLOCK_BN254G1_XMD:KECCAK-256_SVDW_RO_H1_'),
        H2: Buffer.from('BLOCKLOCK_BN254_XMD:KECCAK-256_H2_'),
        H3: Buffer.from('BLOCKLOCK_BN254_XMD:KECCAK-256_H3_'),
        H4: Buffer.from('BLOCKLOCK_BN254_XMD:KECCAK-256_H4_'),
    }
}

function extractLogs<T extends Interface, E extends EventFragment>(
    iface: T,
    receipt: TransactionReceipt,
    contractAddress: string,
    event: E,
  ): Array<Result> {
    return receipt.logs
      .filter((log) => log.address.toLowerCase() === contractAddress.toLowerCase())
      .map((log) => iface.decodeEventLog(event, log.data, log.topics));
  }

function extractSingleLog<T extends Interface, E extends EventFragment>(
    iface: T,
    receipt: TransactionReceipt,
    contractAddress: string,
    event: E,
  ): Result {
    const events = extractLogs(iface, receipt, contractAddress, event);
    if (events.length === 0) {
      throw Error(`contract at ${contractAddress} didn't emit the ${event.name} event`);
    }
    return events[0];
  }

async function encryptAndRegister(
    message: Uint8Array,
    blockHeight: bigint,
    pk: G2 = BLOCKLOCK_DEFAULT_PUBLIC_KEY,
  ): Promise<{
    id: string;
    receipt: object;
    ct: Ciphertext;
  }> {
    const ct = encrypt(message, blockHeight, pk);
    const rpc = new ethers.JsonRpcProvider(rpcAddr)
    const wallet = new ethers.Wallet(privateKey, rpc)

    const auctionContract = SimpleAuction__factory.connect(contractAddr, rpc)

    const lowerPrice = ethers.parseEther("0.1");
    const tx = await auctionContract.connect(wallet).sealedBid(encodeCiphertextToSolidity(ct), { value: lowerPrice });
    const receipt = await tx.wait(1);
    if (!receipt) {
      throw new Error("transaction has not been mined");
    }

    if (!receipt) {
        throw new Error("transaction has not been mined");
      }
      const iface = SimpleAuction__factory.createInterface();
      const [bidID, , ] = extractSingleLog(
        iface,
        receipt,
        await auctionContract.getAddress(),
        iface.getEvent("NewBid"),
      );

    return {
      id: bidID.toString(),
      receipt: receipt,
      ct,
    };
  }

async function main() {
    const msg = ethers.parseEther(message.toString());
    console.log(`encrypting bid amount ${message.toString()} ether as ${msg} wei`)
    const msgBytes = AbiCoder.defaultAbiCoder().encode(["uint256"], [msg]);
    const encodedMessage = getBytes(msgBytes);

    const blockHeight = BigInt(blocknumber)
    const { id, receipt, ct } = await encryptAndRegister(encodedMessage, blockHeight, BLOCKLOCK_DEFAULT_PUBLIC_KEY);
    console.log(`request id: ${id}`)
    console.log(`bid transaction receipt: ${receipt}`)
    console.log(`Ciphertext: ${ct}`)
}   

main()
    .then(() => {
        process.exit(0)
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })
    
function encrypt(message: Uint8Array, blockHeight: bigint, pk: G2) {
    const identity = blockHeightToBEBytes(blockHeight)
    return encrypt_towards_identity_g1(message, identity, pk, BLOCKLOCK_IBE_OPTS)
}

function encodeCiphertextToSolidity(ciphertext: Ciphertext) {
    const u: { x: [bigint, bigint], y: [bigint, bigint] } = {
        x: [ciphertext.U.x.c0, ciphertext.U.x.c1],
        y: [ciphertext.U.y.c0, ciphertext.U.y.c1]
    }

    return {
        u,
        v: ciphertext.V,
        w: ciphertext.W,
    }
}

function blockHeightToBEBytes(blockHeight: bigint) {
    // Assume a block height < 2**64
    const buffer = new ArrayBuffer(32)
    const dataView = new DataView(buffer)
    dataView.setBigUint64(0, (blockHeight >> 192n) & 0xffff_ffff_ffff_ffffn)
    dataView.setBigUint64(8, (blockHeight >> 128n) & 0xffff_ffff_ffff_ffffn)
    dataView.setBigUint64(16, (blockHeight >> 64n) & 0xffff_ffff_ffff_ffffn)
    dataView.setBigUint64(24, blockHeight & 0xffff_ffff_ffff_ffffn)

    return new Uint8Array(buffer)
}
