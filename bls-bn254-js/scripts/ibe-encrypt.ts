import { hexlify } from 'ethers'
import { encrypt_towards_identity_g1, serializeCiphertext } from '../src'
import { Command } from 'commander'

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

async function main() {
    const msg = message
    const encodedMessage = new Uint8Array(Buffer.from(msg))
    const encodedBlockNumber = blockHeightToBEBytes(BigInt(blocknumber))
    const ciphertext =  encrypt_towards_identity_g1(encodedMessage, encodedBlockNumber, COMMITTEE_PK)
    console.log("Ciphertext", hexlify(serializeCiphertext(ciphertext)))
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

main()
    .then(() => {
        process.exit(0)
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })
    