import express from "express"
import {AddressLike, ethers, isAddress, JsonRpcProvider, Wallet, WebSocketProvider} from "ethers"

const RPC_URL = process.env.HOSE_RPC_URL ?? "http://localhost:8545"
const PRIVATE_KEY = process.env.HOSE_PRIVATE_KEY ?? "640956938a00da1be5f1335d0e3a6dba6f57d832b10fd6b0278b980c43087662"
const PORT = process.env.HOSE_PORT ? Number.parseInt(process.env.HOSE_PORT) : 8082
const TOKENS_PER_REQUEST = process.env.HOSE_TOKENS_PER_REQUEST ? Number.parseInt(process.env.HOSE_TOKENS_PER_REQUEST) : 20
const REQUESTS_PER_DAY = process.env.HOSE_REQUESTS_PER_DAY ? Number.parseInt(process.env.HOSE_REQUESTS_PER_DAY) : 24
const MIN_CONFIRMATIONS = process.env.HOSE_MINIMUM_CONFIRMATIONS ? Number.parseInt(process.env.HOSE_MINIMUM_CONFIRMATIONS) : 1
const addressToTokens: Record<string, Array<number>> = {}
const ipToTokens: Record<string, Array<number>> = {}

const app = express()
const rpc = RPC_URL.startsWith("ws") ? new WebSocketProvider(RPC_URL) : new JsonRpcProvider(RPC_URL)
const wallet = new Wallet(PRIVATE_KEY, rpc)

app.get("/health", (_: express.Request, res: express.Response) => {
    res.sendStatus(200)
})

app.post("/gimme", tokenFaucet)

app.listen(PORT, () => {
    console.log(`server listening on port ${PORT}`)
})

type RequestParams = express.Request<object, object, object, { address?: string }>

async function tokenFaucet(req: RequestParams, res: express.Response) {
    // check the use has passed in a valid ETH address
    const address = req.query.address
    if (!address) {
        res.sendStatus(400)
            .send(JSON.stringify({error: "you must pass an address as a query param"}))
        return
    }
    if (!isAddress(address)) {
        res.sendStatus(400)
            .send(JSON.stringify({error: "address was of the wrong format"}))
        return
    }

    // we can't rate limit users who don't pass an IP, so let's just block them all
    const ip = req.ip
    if (!ip) {
        res.sendStatus(400)
            .send(JSON.stringify({error: "you didn't pass an IP in the request headers, so we won't give you tokens"}))
        return
    }

    // where have I seen this wonderful solution before??
    const ipRequests = trimmedTimestamps(ipToTokens[ip])
    const addressRequests = trimmedTimestamps(addressToTokens[address])
    if (ipRequests.length >= REQUESTS_PER_DAY || addressRequests.length >= REQUESTS_PER_DAY) {
        res.sendStatus(429)
            .send(JSON.stringify({error: "don't be greedy now!"}))
        return
    }

    try {
        console.log(`sending ${TOKENS_PER_REQUEST} ETH to ${address}`)
        await sendTokens(address, TOKENS_PER_REQUEST)
        console.log(`sent ${TOKENS_PER_REQUEST} ETH to ${address} successfully`)
        res.sendStatus(204)

        const now = Date.now()
        ipToTokens[ip] = [...ipRequests, now]
        addressToTokens[ip] = [...addressRequests, now]
    } catch (err) {
        console.error(err)
        res.sendStatus(500).send(JSON.stringify({error: "there was an error fulfilling your request"}))
    }
}

// trimmedTimestamps takes an array of numbers (timestamps), and trims off any that are greater than 24 hours ago
function trimmedTimestamps(arr: Array<number> | undefined): Array<number> {
    if (!arr) {
        return []
    }
    const twentyFourHours = 24 * 60 * 60 * 1000
    const twentyFourHoursAgo = Date.now() - twentyFourHours
    return arr.filter(it => it >= twentyFourHoursAgo)
}

// sendTokens sends native tokens to a given address
async function sendTokens(to: AddressLike, tokenCount: number): Promise<void> {
    const value = ethers.parseEther(tokenCount.toString(10))
    const tx = await wallet.sendTransaction({to, value})
    await tx.wait(MIN_CONFIRMATIONS)
}
