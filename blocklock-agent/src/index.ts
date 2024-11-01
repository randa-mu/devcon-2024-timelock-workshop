import * as http from "node:http"
import { Command, Option } from "commander"
import { ethers, AbiCoder, AddressLike, getBytes, isHexString, toUtf8Bytes, Wallet, ContractTransactionResponse } from "ethers"
import { G1, G2 } from "mcl-wasm"
import { BlsBn254 } from "@randamu/bls-bn254-js/src"
import { type TypedContractEvent, TypedListener } from "./generated/common"
import { createProviderWithRetry } from "./provider"
import {
    BlocklockSender,
    BlocklockSender__factory,
    BlocklockSignatureScheme,
    BlocklockSignatureScheme__factory,
    SignatureSchemeAddressProvider,
    SignatureSchemeAddressProvider__factory,
    SignatureSender,
    SignatureSender__factory,
    SimpleAuction,
    SimpleAuction__factory
} from "./generated"
import { SignatureRequestedEvent } from "./generated/SignatureSender"

const program = new Command()

const defaultPort = "8080"
const defaultRPC = "http://localhost:8545"
const defaultPrivateKey = "0xecc372f7755258d11d6ecce8955e9185f770cc6d9cff145cca753886e1ca9e46"
const defaultBlsKey = "0x58aabbe98959c4dcb96c44c53be7e3bb980791fc7a9e03445c4af612a45ac906"

program
    .addOption(new Option("--port <port>", "The port to host the healthcheck on")
        .default(defaultPort)
        .env("TIMELOCK_PORT")
    )
    .addOption(new Option("--rpc-url <rpc-url>", "The websockets URL to connect to the blockchain from")
        .default(defaultRPC)
        .env("TIMELOCK_RPC_URL")
    )
    .addOption(new Option("--private-key <private-key>", "The private key to use for execution")
        .default(defaultPrivateKey)
        .env("TIMELOCK_PRIVATE_KEY")
    )
    .addOption(new Option("--bls-key <bls-key>", "The BLS private key to use for signing")
        .default(defaultBlsKey)
        .env("TIMELOCK_BLS_PRIVATE_KEY")
    )

const options = program
    .parse()
    .opts()


const SCHEME_ID = "BN254-BLS-BLOCKLOCK";
const DST = "IBE_BN254G1_XMD:KECCAK-256_SVDW_RO_H1_";
// Auction smart contract configuration parameters
const durationBlocks = 50; // blocks
const reservePrice = 0.1; // ether
const reservePriceInWei = ethers.parseEther(reservePrice.toString(10))
const highestBidPaymentWindowBlocks = 10; // blocks

async function main() {
    // set up all our plumbing
    const port = parseInt(options.port)
    console.log("deploying all required smart contracts ...")
    const bls = await BlsBn254.create()
    const { pubKey, secretKey } = bls.createKeyPair(options.blsKey)

    const rpc = await createProviderWithRetry(options.rpcUrl)
    const wallet = new Wallet(options.privateKey, rpc)

    // deploy the contracts and start listening for signature requests
    const schemeProviderContract = await deploySchemeProvider(wallet)
    const schemeProviderAddress = await schemeProviderContract.getAddress()
    console.log(`scheme contract deployed to ${schemeProviderAddress}`)

    const blocklockSchemeContract = await deployBlocklockScheme(wallet, schemeProviderContract)
    const blocklockSchemeContractAddr = await blocklockSchemeContract.getAddress()
    console.log(`blocklock scheme contract deployed to ${blocklockSchemeContractAddr}`)

    const signatureSenderContract = await deploySignatureSender(bls, wallet, pubKey, schemeProviderAddress)
    const signatureSenderContractAddr = await signatureSenderContract.getAddress()
    console.log(`signature sender contract deployed to ${signatureSenderContractAddr}`)

    const blocklockContract = await deployBlocklock(wallet, signatureSenderContractAddr)
    const blocklockContractAddr = await blocklockContract.getAddress()
    console.log(`blocklock contract deployed to ${blocklockContractAddr}`)

    const auctionContract = await deployAuction(wallet, blocklockContractAddr)
    const auctionContractAddr = await auctionContract.getAddress()
    console.log(`simple auction contract deployed to ${auctionContractAddr}`)
    console.log("\nsimple auction contract configuration parameters");
    console.log("Auction duration in blocks:", durationBlocks);
    console.log("Auction end block number:", await auctionContract.auctionEndBlock());
    console.log("Auction reserve price in ether:", reservePrice);
    console.log("Window for fulfilling highest bid in blocks post-auction:", highestBidPaymentWindowBlocks);

    const blocklockNumbers = new Map()
    await signatureSenderContract.addListener("SignatureRequested", createSignatureListener(bls, blocklockNumbers))

    // spin up a healthcheck HTTP server
    http.createServer((_, res) => {
        res.writeHead(200)
        res.end()
    }).listen(port, "0.0.0.0", () => console.log(`timelock writer running on port ${port}`))

    // Triggered on each block to check if there was a blocklock request for that round
    // We may skip some blocks depending on the rpc.pollingInterval value
    rpc.pollingInterval = 1000//ms
    rpc.on("block", async (blockHeight: number) => {
        const res = blocklockNumbers.get(BigInt(blockHeight))
        if (!res) {
            // no requests for this block
            console.log(`no timelock requests for block ${blockHeight}`)
            return
        }

        const { m, ids } = res

        console.log(`creating a timelock signature for block ${blockHeight}`)
        const signature = bls.sign(m, secretKey).signature
        const sig = bls.serialiseG1Point(signature)
        const sigBytes = AbiCoder.defaultAbiCoder().encode(["uint256", "uint256"], [sig[0], sig[1]])
        // Fulfil each request
        const txs: ContractTransactionResponse[] = []
        const nonce = await wallet.getNonce("latest");
        for (let i = 0; i < ids.length; i++) {
            try {
                const id = ids[i]
                console.log(`fulfilling signature request ${id}`)
                txs.push(await signatureSenderContract.fulfilSignatureRequest(id, sigBytes, { nonce: nonce + i }))
            } catch (e) {
                console.log(e)
            }
        }

        for (const tx of txs) {
            try {
                await tx.wait(1)
                console.log(`fulfilled signature request`)
            } catch (e) {
                console.log(e)
            }
        }
    })

    await keepAlive()
}

/**
 * Listen for blocklock signature request for the BN254-BLS-BLOCKLOCK scheme
 */
function createSignatureListener(
    bls: BlsBn254,
    requestedBlocklocks: Map<bigint, { m: G1, ids: bigint[] }>,
): TypedListener<TypedContractEvent<
    SignatureRequestedEvent.InputTuple,
    SignatureRequestedEvent.OutputTuple,
    SignatureRequestedEvent.OutputObject
>> {
    return async (requestID, callback, schemeID, message, messageHashToSign, condition,) => {
        if (schemeID != SCHEME_ID) {
            // Silently ignore requests of an unsupported scheme id
            return;
        }

        console.log(`received signature request ${requestID}`)
        console.log(`${callback}, ${schemeID}`)
        if (message != condition) {
            console.log(`received signature request with message != condition`)
            return
        }

        const msgBytes = isHexString(message) ? getBytes(message) : toUtf8Bytes(message)
        const m = bls.hashToPoint(Buffer.from(DST), msgBytes)
        const serM = bls.serialiseG1Point(m)
        const mBytes = AbiCoder.defaultAbiCoder().encode(["uint256", "uint256"], [serM[0], serM[1]])
        if (mBytes != messageHashToSign) {
            console.log(`received signature request with H(message) != messageHashToSign`)
            return
        }

        // Decode the condition into a blockHeight
        const hexCondition = isHexString(condition) ? condition : Buffer.from(toUtf8Bytes(condition)).toString('hex')
        const blockHeight = BigInt(hexCondition)

        // Get a reference to the object in the map
        const requests = requestedBlocklocks.get(blockHeight)
        if (!requests) {
            // Store new object
            requestedBlocklocks.set(blockHeight, { m, ids: [requestID] })
        } else {
            // Update the array object in the map
            requests.ids.push(requestID)
        }
        console.log(`registered signature request \`${requestID}\` at blockHeight \`${blockHeight.toString()}\``)
    }
}

/**
 * Deploy the signature scheme address provider contract
 */
async function deploySchemeProvider(wallet: Wallet): Promise<SignatureSchemeAddressProvider> {
    const contract = await new SignatureSchemeAddressProvider__factory(wallet).deploy()
    return contract.waitForDeployment()
}

/**
 * Deploy the blocklock signature scheme contract, and register it in the scheme provider
 */
async function deployBlocklockScheme(wallet: Wallet, schemeProviderContract: SignatureSchemeAddressProvider): Promise<BlocklockSignatureScheme> {
    const contract = await new BlocklockSignatureScheme__factory(wallet).deploy()
    const scheme = await contract.waitForDeployment()

    console.log("registering blocklock scheme")
    const tx = await schemeProviderContract.updateSignatureScheme(SCHEME_ID, await scheme.getAddress())
    await tx.wait(1)

    return scheme
}

/**
 * Deploy the signature sender contract
 */
async function deploySignatureSender(bls: BlsBn254, wallet: Wallet, blsPublicKey: G2, schemeProvider: AddressLike): Promise<SignatureSender> {
    const [x1, x2, y1, y2] = bls.serialiseG2Point(blsPublicKey)
    const contract = await new SignatureSender__factory(wallet).deploy([x1, x2], [y1, y2], schemeProvider)
    return contract.waitForDeployment()
}

/**
 * Deploy the blocklock contract
 */
async function deployBlocklock(wallet: Wallet, signatureSenderContractAddr: AddressLike): Promise<BlocklockSender> {
    const contract = await new BlocklockSender__factory(wallet).deploy(signatureSenderContractAddr)
    return contract.waitForDeployment()
}

/**
 * Deploy the auction contract
 */
async function deployAuction(wallet: Wallet, blocklockContractAddr: AddressLike): Promise<SimpleAuction> {
    const contract = await new SimpleAuction__factory(wallet).deploy(
        durationBlocks, 
        reservePriceInWei, 
        highestBidPaymentWindowBlocks,
        blocklockContractAddr
    )
    return contract.waitForDeployment()
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
