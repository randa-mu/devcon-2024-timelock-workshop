import { hexlify } from 'ethers'
import { encrypt_towards_identity_g1, serializeCiphertext, decrypt_towards_identity_g1, get_identity_g1 } from '../src'
import { bn254 } from "../src/crypto/bn254"

async function main() {
    const m = new Uint8Array(Buffer.from('IBE BN254 Consistency Test'))
    const identity = Buffer.from('TEST')
    const identity_g1 = bn254.G1.ProjectivePoint.fromAffine(await get_identity_g1(identity))

    const x = bn254.G1.normPrivateKeyToScalar(bn254.utils.randomPrivateKey())
    const X_G2 = bn254.G2.ProjectivePoint.BASE.multiply(x).toAffine()
    const sig = identity_g1.multiply(x).toAffine()

    const ct = await encrypt_towards_identity_g1(m, identity, X_G2)
    const m2 = await decrypt_towards_identity_g1(ct, sig)
    console.log("ciphertext as hex:", hexlify(serializeCiphertext(ct)))
    console.log("\ndecrypted message as hex:", hexlify(m2))
    console.log("\ndecrypted message as plain text:", hexToString(hexlify(m2))) // returns 'IBE BN254 Consistency Test'
}

main()

// Convert hex string to string
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