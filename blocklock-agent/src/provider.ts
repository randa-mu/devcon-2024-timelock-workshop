import {ethers} from "ethers"

export async function createProviderWithRetry(url: string, maxRetries = 20, retryDelay = 1000) {
    try {
        const provider = new ethers.JsonRpcProvider(url)
        // if we can fetch the block number successfully, then we're connected
        await provider.getBlockNumber()
        console.log("Connected to JSON-RPC endpoint.")
        return provider
    } catch (err) {
        if (maxRetries <= 1) {
            throw err
        }
        console.error("Connection failed. Retrying...")
        await new Promise((resolve) => setTimeout(resolve, retryDelay))
        return createProviderWithRetry(url, maxRetries - 1, retryDelay)
    }
}
