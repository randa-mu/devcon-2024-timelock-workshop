import { AbiCoder, BytesLike, getBytes } from 'ethers'
import { encrypt_towards_identity_g1, decrypt_g1_with_preprocess, get_identity_g1, preprocess_decryption_key_g1, IbeOpts, Ciphertext } from '../src'
import { bn254 } from "../src/crypto/bn254"
import { keccak_256 } from "@noble/hashes/sha3"

const COMMITTEE_PK = {
    x: {
        c0: BigInt(17445541620214498517833872661220947475697073327136585274784354247720096233162n),
        c1: BigInt(18268991875563357240413244408004758684187086817233527689475815128036446189503n),
    },
    y: {
        c0: BigInt(11401601170172090472795479479864222172123705188644469125048759621824127399516n),
        c1: BigInt(8044854403167346152897273335539146380878155193886184396711544300199836788154n),
    },
}
const defaultBlsKey = "0x58aabbe98959c4dcb96c44c53be7e3bb980791fc7a9e03445c4af612a45ac906"

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

async function main() {
    const m = new Uint8Array(Buffer.from('IBE BN254 Consistency Test'))
    const identity = Buffer.from('TEST')
    const identity_g1 = bn254.G1.ProjectivePoint.fromAffine(await get_identity_g1(identity))

    const x = bn254.G1.normPrivateKeyToScalar(bn254.utils.randomPrivateKey())
    const X_G2 = bn254.G2.ProjectivePoint.BASE.multiply(x).toAffine()
    const sig = identity_g1.multiply(x).toAffine()

    const ct = await encrypt_towards_identity_g1(m, identity, X_G2)
    const decryption_key = await preprocess_decryption_key_g1(ct, sig)

    console.log(decryption_key)
    const m2 = decrypt_g1_with_preprocess(ct, decryption_key)

    console.log(uint8ArrayToUTF8String(m))
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

function parseSolidityCiphertext(ctBytes: BytesLike) {
    const ct = AbiCoder.defaultAbiCoder().decode(["tuple(tuple(uint256[2] x, uint256[2] y) u, bytes v, bytes w)"], ctBytes)[0]
    
    const uX0 = ct.u.x[0]
    const uX1 = ct.u.x[1]
    const uY0 = ct.u.y[0]
    const uY1 = ct.u.y[1]
    return {
        U: {x: {c0: uX0, c1: uX1}, y: {c0: uY0, c1: uY1}},
        V: getBytes(ct.v),
        W: getBytes(ct.w),
    }
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


function hexToString(hexString: string) {
    // Remove '0x' prefix if it exists
    if (hexString.startsWith("0x")) {
        hexString = hexString.slice(2);
    }

    // Ensure the hex string has an even length
    if (hexString.length % 2 !== 0) {
        throw new Error("Invalid hex string");
    }

    // Create a string to store the decoded characters
    let result = '';

    // Loop through each pair of hex characters
    for (let i = 0; i < hexString.length; i += 2) {
        // Convert hex to decimal, then to character
        const byte = parseInt(hexString.substr(i, 2), 16);
        result += String.fromCharCode(byte);
    }

    return result;
}

function hexToUint8Array(hex: string) {
    // Remove '0x' prefix if it exists
    if (hex.startsWith('0x')) {
      hex = hex.slice(2);
    }
  
    // Ensure the hex string has an even length
    if (hex.length % 2 !== 0) {
      throw new Error("Invalid hex string length");
    }
  
    // Create a Uint8Array to store the converted values
    const uint8Array = new Uint8Array(hex.length / 2);
  
    // Loop through the hex string in pairs of 2 characters
    for (let i = 0; i < hex.length; i += 2) {
      uint8Array[i / 2] = parseInt(hex.substr(i, 2), 16); // Convert each pair to byte
    }
  
    return uint8Array;
}
