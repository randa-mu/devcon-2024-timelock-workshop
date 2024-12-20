import * as http from "node:http"
import {Command, Option} from "commander"
import {
    AbiCoder,
    BigNumberish,
    getBytes,
    getBigInt,
    isHexString,
    toUtf8Bytes,
    Wallet,
    NonceManager,
    ContractTransactionResponse,
} from "ethers"
import {G1} from "mcl-wasm"
import {
    BlsBn254,
    Ciphertext,
    connectDeployer,
    createProviderWithRetry,
    DecryptionSender__factory,
    factoryAddress,
    IbeOpts,
    preprocess_decryption_key_g1,
    SignatureSchemeAddressProvider__factory,
    SimpleAuction__factory,
} from "@randamu/bls-bn254-js/src"
import {TypedContractEvent, TypedListener} from "@randamu/bls-bn254-js/src/generated/common"
import {
    BLOCKLOCK_SCHEME_ID,
    deployAuction,
    deployBlocklock,
    deployBlocklockScheme,
    deployDecryptionSender,
    deploySchemeProvider,
} from "./deployments"
import { keccak_256 } from "@noble/hashes/sha3"
import { DecryptionRequestedEvent } from "@randamu/bls-bn254-js/src/generated/DecryptionSender"
import { TypesLib as BlocklockTypes } from "@randamu/bls-bn254-js/src/generated/BlocklockSender"


const program = new Command()

const defaultPort = "8080"
const defaultRPC = "http://localhost:8545"
const defaultPrivateKey = "0xecc372f7755258d11d6ecce8955e9185f770cc6d9cff145cca753886e1ca9e46"
const defaultBlsKey = "0x58aabbe98959c4dcb96c44c53be7e3bb980791fc7a9e03445c4af612a45ac906"

export const BLOCKLOCK_IBE_OPTS: IbeOpts = {
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

program
    .addOption(new Option("--port <port>", "The port to host the healthcheck on")
        .default(defaultPort)
        .env("BLOCKLOCK_PORT")
    )
    .addOption(new Option("--rpc-url <rpc-url>", "The websockets/HTTP URL to connect to the blockchain from")
        .default(defaultRPC)
        .env("BLOCKLOCK_RPC_URL")
    )
    .addOption(new Option("--private-key <private-key>", "The private key to use for execution")
        .default(defaultPrivateKey)
        .env("BLOCKLOCK_PRIVATE_KEY")
    )
    .addOption(new Option("--bls-key <bls-key>", "The BLS private key to use for signing")
        .default(defaultBlsKey)
        .env("BLOCKLOCK_BLS_PRIVATE_KEY")
    )

const options = program
    .parse()
    .opts()


async function main() {
    // set up all our plumbing
    const port = parseInt(options.port)
    const rpc = await createProviderWithRetry(options.rpcUrl, {pollingInterval: 1000})
    const wallet = new NonceManager(new Wallet(options.privateKey, rpc))

    console.log("waiting for contract deployment - relax, this will take a minute...")
    await connectDeployer(factoryAddress, wallet)
    console.log("deployer connected")
    
    const bls = await BlsBn254.create()
    const {pubKey, secretKey} = bls.createKeyPair(options.blsKey)
    
    // deploy the contracts and start listening for signature requests
    const schemeProviderAddr = await deploySchemeProvider(wallet)

    const schemeProviderContract = SignatureSchemeAddressProvider__factory.connect(schemeProviderAddr, wallet)
    console.log(`scheme contract deployed to ${schemeProviderAddr}`)

    const blocklockSchemeAddr = await deployBlocklockScheme(wallet)
    const tx = await schemeProviderContract.updateSignatureScheme(BLOCKLOCK_SCHEME_ID, blocklockSchemeAddr)
    await tx.wait(1)
    console.log(`blocklock scheme contract deployed to ${blocklockSchemeAddr}`)

    const decryptionSenderAddr = await deployDecryptionSender(bls, wallet, pubKey, schemeProviderAddr)
    const decryptionSenderContract = DecryptionSender__factory.connect(decryptionSenderAddr, wallet)
    console.log(`decryption sender contract deployed to ${decryptionSenderAddr}`)

    const blocklockAddr = await deployBlocklock(wallet, decryptionSenderAddr)
    console.log(`blocklock contract deployed to ${blocklockAddr}`)

    const auctionAddr = await deployAuction(wallet, blocklockAddr)
    console.log(`auction contract deployed to ${auctionAddr}`)
    
    const auctionContract = SimpleAuction__factory.connect(auctionAddr, wallet)
    console.log(`auction end block ${await auctionContract.auctionEndBlock()}`)

    const blocklockNumbers = new Map()
    await decryptionSenderContract.addListener("DecryptionRequested", createDecryptionListener(bls, blocklockNumbers))

    // Triggered on each block to check if there was a blocklock request for that round
    // We may skip some blocks depending on the rpc.pollingInterval value
    await rpc.on("block", async (blockHeight: BigNumberish) => {
        const res = blocklockNumbers.get(getBigInt(blockHeight))
        if (!res) {
            // no requests for this block
            return
        }

        const { m, reqs } = res

        console.log(`creating a blocklock signature for block ${blockHeight}`)
        const signature = bls.sign(m, secretKey).signature
        const sig = bls.serialiseG1Point(signature)
        const sigBytes = AbiCoder.defaultAbiCoder().encode(["uint256", "uint256"], [sig[0], sig[1]])
        // Fulfil each request
        const txs: ContractTransactionResponse[] = []
        const nonce = await wallet.getNonce("latest");
        for (let i = 0; i < reqs.length; i++) {
            try {
                const {id, ct} = reqs[i]
                console.log(`fulfilling decryption request ${id}`)
                const decryption_key = preprocess_decryption_key_g1(ct, {x: sig[0], y: sig[1]}, BLOCKLOCK_IBE_OPTS)
                txs.push(await decryptionSenderContract.fulfilDecryptionRequest(id, decryption_key, sigBytes, { nonce: nonce + i }))
            } catch (e) {
                console.error(`Error fulfilling decryption request ${e}`)
            }
        } 

        for (const tx of txs) {
            try {
                await tx.wait(1)
                console.log(`fulfilled decryption request`)
            } catch (e) {
                console.error(`Error fulfilling decryption request: ${e}`)
            }
        }
    })

    // spin up a healthcheck HTTP server
    http.createServer((_, res) => {
        res.writeHead(200)
        res.end()
    }).listen(port, "0.0.0.0", () => console.log(`blocklock writer running on port ${port}`))

    await keepAlive()
}

/**
 * Listen for blocklock signature request for the BN254-BLS-BLOCKLOCK scheme
 */
function createDecryptionListener(
    bls: BlsBn254,
    requestedBlocklocks: Map<bigint, { m: G1, reqs: {ct: Ciphertext, id: bigint}[] }>,
): TypedListener<TypedContractEvent<
    DecryptionRequestedEvent.InputTuple,
    DecryptionRequestedEvent.OutputTuple,
    DecryptionRequestedEvent.OutputObject
>> {
    return async (requestID, callback, schemeID, condition, ciphertext) => {
        if (schemeID != BLOCKLOCK_SCHEME_ID) {
            // Ignore requests of an unsupported scheme id
            console.log(`ignoring decryption request for unsupported scheme id (\`${schemeID}\`)`)
            return;
        }

        console.log(`received decryption request ${requestID}`)
        console.log(`${callback}, ${schemeID}`)

        const conditionBytes = isHexString(condition) ? getBytes(condition) : toUtf8Bytes(condition)
        const m = bls.hashToPoint(BLOCKLOCK_IBE_OPTS.dsts.H1_G1, conditionBytes)

        // Decode the condition into a blockHeight
        const hexCondition = Buffer.from(conditionBytes).toString("hex")
        const blockHeight = BigInt("0x" + hexCondition)

        // Deserialize the ciphertext
        const ct = parseSolidityCiphertext(ciphertext)

        // Get a reference to the object in the map
        const requests = requestedBlocklocks.get(blockHeight)
        if (!requests) {
            // Store new object
            requestedBlocklocks.set(blockHeight, {m, reqs: [{ct, id: requestID }]})
        } else {
            // Update the array object in the map
            requests.reqs.push({ct, id: requestID})
        }
        console.log(`registered decryption request \`${requestID}\` at blockHeight \`${blockHeight.toString(10)}\``)
    }
}

function parseSolidityCiphertext(ciphertext: string): Ciphertext {
    const ctBytes = getBytes(ciphertext)
    const ct: BlocklockTypes.CiphertextStructOutput = AbiCoder.defaultAbiCoder().decode(["tuple(tuple(uint256[2] x, uint256[2] y) u, bytes v, bytes w)"], ctBytes)[0]
    
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

async function keepAlive() {
    return new Promise<void>((resolve) => {
        process.stdin.resume()
        process.on("SIGINT", () => {
            console.log("Shutting down listener...");
            resolve()
        })
    })
}

main()
    .then(() => {
        process.exit(0)
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })
