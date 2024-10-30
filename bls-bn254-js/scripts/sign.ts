import { getBytes, isHexString, toUtf8Bytes } from 'ethers'
import { BlsBn254, kyberMarshalG1, kyberMarshalG2 } from '../src'
import { Command } from 'commander'

// Sign with BLS on BN254
//
// Usage
//  yarn bls:sign --privatekey "0xprivatekey" --message "message to sign" --domain [optional DST]

const DEFAULT_DOMAIN = 'BLS_SIG_BN254G1_XMD:KECCAK-256_SSWU_RO_NUL_'

// Define the CLI command and arguments using `commander`
const program = new Command()

program
    .option('--privatekey <privatekey>', 'The private key to use in generating a key pair for message signing', "58aabbe98959c4dcb96c44c53be7e3bb980791fc7a9e03445c4af612a45ac906")
    .requiredOption('--message <message>', 'Message to be hashed')
    .option('--domain <domain>', 'Domain separator for hashing', DEFAULT_DOMAIN)

program.parse(process.argv)

// Extract parsed options
const options = program.opts()
const privatekey = options.privatekey
const message: string = options.message
const domain: string = options.domain


async function main() {
    const bls = await BlsBn254.create()
    const _secretKey = privatekey as `0x${string}`
    const msg = message
    const dst = domain
    const msgBytes = isHexString(msg) ? getBytes(msg) : toUtf8Bytes(msg)
    const dstBytes = isHexString(dst) ? getBytes(dst) : toUtf8Bytes(dst)
    const point = bls.hashToPoint(dstBytes, msgBytes)
    const { secretKey, pubKey } = bls.createKeyPair(_secretKey)
    const { signature } = bls.sign(point, secretKey)
    console.log(
        JSON.stringify(
            {
                pubKey: kyberMarshalG2(pubKey),
                signature: kyberMarshalG1(signature),
            },
            null,
            4,
        ),
    )
}

main()
    .then(() => {
        process.exit(0)
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })
