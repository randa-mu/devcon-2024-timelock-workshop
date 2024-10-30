import { hexlify } from 'ethers'
import { encrypt_towards_identity_g1, serializeCiphertext, decrypt_towards_identity_g1, get_identity_g1 } from '../src'
import { bn254 } from "../src/crypto/bn254"
import { Command } from 'commander'

// Encrypt message with Identity-based Encryption (IBE)
//
// Usage
//  yarn ibe:encrypt --message "plaintext message to timelock encrypt" --blocknumber "block number when message can be decrypted"

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

const COMMITTEE_PK = {
    x: {
        c0: BigInt("0x2691d39ecc380bfa873911a0b848c77556ee948fb8ab649137d3d3e78153f6ca"),
        c1: BigInt("0x2863e20a5125b098108a5061b31f405e16a069e9ebff60022f57f4c4fd0237bf"),
    },
    y: {
        c0: BigInt("0x193513dbe180d700b189c529754f650b7b7882122c8a1e242a938d23ea9f765c"),
        c1: BigInt("0x11c939ea560caf31f552c9c4879b15865d38ba1dfb0f7a7d2ac46a4f0cae25ba"),
    },
}

async function main() {
    const msg = message
    const encodedMessage = Buffer.from(msg)
    const encodedBlockNumber = Buffer.from(blocknumber)
    const ciphertext =  encrypt_towards_identity_g1(encodedMessage, encodedBlockNumber, COMMITTEE_PK)
    console.log("Ciphertext", hexlify(serializeCiphertext(ciphertext)))
}


main()
    .then(() => {
        process.exit(0)
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })
