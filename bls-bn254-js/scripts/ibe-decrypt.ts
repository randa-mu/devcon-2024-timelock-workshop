import { decrypt_towards_identity_g1, deserializeCiphertext } from '../src'
import { bn254 } from "../src/crypto/bn254"
import { hexlify } from 'ethers'
import { Command } from 'commander'

// Decrypt message with Identity-based Encryption (IBE)
//
// Usage
//  yarn ibe:decrypt --ciphertext "the ciphertext to decrypt" --signature "the signature over the ciphertext which is the decryption key"

// Define the CLI command and arguments using `commander`
const program = new Command()

program
    .requiredOption('--ciphertext <ciphertext>', 'Ciphertext to be decrypted')
    .requiredOption('--signature <signature>', 'Signature over ciphertext which is the decryption key')

program.parse(process.argv)

// Extract parsed options
const options = program.opts()
const ciphertext: string = options.ciphertext
const signature: string = options.signature

async function main() {
    const cipher = ciphertext
    const deserializedCiphertext = deserializeCiphertext(Uint8Array.from(Buffer.from(cipher, 'hex')))
    const signatureAsG1Point = bn254.ShortSignature.fromHex(Buffer.from(signature, 'hex'))
    const message = await decrypt_towards_identity_g1(deserializedCiphertext, signatureAsG1Point)
    console.log("Decrypted message as hex:", hexlify(message))
    console.log("Decrypted message as plaintext string:", hexToString(hexlify(message)))
}

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


main()
    .then(() => {
        process.exit(0)
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })
