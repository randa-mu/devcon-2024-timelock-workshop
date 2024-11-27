import { hexlify, AbiCoder, BytesLike, getBytes, isHexString, toUtf8Bytes } from 'ethers'
import { BlsBn254, encrypt_towards_identity_g1, serializeCiphertext, IbeOpts, G2, Ciphertext, preprocess_decryption_key_g1, decrypt_g1_with_preprocess } from '../src'
import { Command } from 'commander'
import { keccak_256 } from "@noble/hashes/sha3"

// Encrypt message with Identity-based Encryption (IBE)
//
// Usage
//  yarn timelock:encrypt --message "plaintext message to timelock encrypt" --blocknumber "block number when message can be decrypted"

// Define the CLI command and arguments using `commander`
const program = new Command()

program
    .requiredOption('--message <message>', 'Message to be encrypted')
    .requiredOption('--blocknumber <blocknumber>', 'Block number when message can be decrypted')

program.parse(process.argv)

// Extract parsed options
const options = program.opts()
const message: string = options.message
const blocknumber: string = options.blocknumber


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

const defaultBlsKey = "0x58aabbe98959c4dcb96c44c53be7e3bb980791fc7a9e03445c4af612a45ac906"

async function main() {
    const msg = message
    const encodedMessage = new Uint8Array(Buffer.from(msg))
    const identity = blockHeightToBEBytes(BigInt(blocknumber))
    const ct = encrypt_towards_identity_g1(encodedMessage, identity, BLOCKLOCK_DEFAULT_PUBLIC_KEY, BLOCKLOCK_IBE_OPTS)
    
    console.log(ct)
    // parseSolidityCiphertext is used to parse ciphertext from smart contract event
    // encodeCiphertextToSolidity is used to create ciphertext solidity input with g2 point formatting
    // ciphertext.U
    console.log("Ciphertext as struct for solidity", encodeCiphertextToSolidity(ct))

    console.log("Ciphertext as struct with hex for solidity", encodeCiphertextToSolidityWithHex(ct))

    console.log("Ciphertext as hex", hexlify(serializeCiphertext(ct)))
    
    // todo separate decrypt step into its own script ibe-decrypt.ts
    const bls = await BlsBn254.create()
    const condition = "0x000000000000000000000000000000000000000000000000000000000000000b" // block number 11
    const conditionBytes = isHexString(condition) ? getBytes(condition) : toUtf8Bytes(condition)
    const m = bls.hashToPoint(BLOCKLOCK_IBE_OPTS.dsts.H1_G1, conditionBytes)
    const hexCondition = Buffer.from(conditionBytes).toString("hex")
    const blockHeight = BigInt("0x" + hexCondition)
    console.log(`Creating signature and decryption key for block height ${blockHeight}`)

    const {pubKey, secretKey} = bls.createKeyPair(defaultBlsKey)
    const signature = bls.sign(m, secretKey).signature
    const sig = bls.serialiseG1Point(signature)

    const sigBytes = AbiCoder.defaultAbiCoder().encode(["uint256", "uint256"], [sig[0], sig[1]])
    const decryption_key = preprocess_decryption_key_g1(ct, {x: sig[0], y: sig[1]}, BLOCKLOCK_IBE_OPTS)
    console.log("signature", sigBytes)
    console.log("decryption key bytes", hexlify(decryption_key))

    console.log(decryption_key)
    
    const m2 = decrypt_g1_with_preprocess(ct, decryption_key, BLOCKLOCK_IBE_OPTS)

    console.log(msg)
    console.log(uint8ArrayToUTF8String(m2))
}

main()
    .then(() => {
        process.exit(0)
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })
    

// helper functions
function uint8ArrayToUTF8String(arr: Uint8Array) {
    const textDecoder = new TextDecoder('utf-8');
    const decodedString = textDecoder.decode(arr);
    return decodedString
}

function uint8ArrayToHex(uint8Array: Uint8Array): string {
    return "0x" + Array.from(uint8Array)
        .map((byte: number) => byte.toString(16).padStart(2, "0")) // Explicitly typing byte as a number
        .join("");
}

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

function encodeCiphertextToSolidityWithHex(ciphertext: Ciphertext) {
    const u: { x: [bigint, bigint], y: [bigint, bigint] } = {
        x: [ciphertext.U.x.c0, ciphertext.U.x.c1],
        y: [ciphertext.U.y.c0, ciphertext.U.y.c1]
    }

    return {
        u,
        v: hexlify(ciphertext.V),
        w: hexlify(ciphertext.W),
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
