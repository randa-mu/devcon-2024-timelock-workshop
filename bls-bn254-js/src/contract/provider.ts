import {AbstractProvider, AbstractSigner, JsonRpcApiProviderOptions, JsonRpcProvider} from "ethers"
import {Deployer, Deployer__factory} from "../generated"
import {withTimeout} from "../index"

export async function createProviderWithRetry(url: string, options: JsonRpcApiProviderOptions = {}, maxRetries = 20, retryDelay = 1000): Promise<AbstractProvider> {
    return withRetry(async () => {
        const provider = new JsonRpcProvider(url, undefined, options)
        // if we can fetch the block number successfully, then we're connected
        await provider.getBlockNumber()
        console.log("Connected to JSON-RPC endpoint.")
        return provider
    }, "Connection failed. Retrying...", maxRetries, retryDelay)
}

export async function connectDeployer(address: string, signer: AbstractSigner): Promise<Deployer> {
    const POLL_INTERVAL = 5000; // 5 seconds interval for polling

    while (true) {  // Infinite loop for continuous polling
        try {
            const deployer = Deployer__factory.connect(address, signer);

            // Wait for the contract deployment confirmation
            await deployer.waitForDeployment();

            // Successfully connected, return the contract instance
            console.log("Successfully connected to Deployer contract!");
            return deployer;
        } catch (error) {
            // Log the retry attempt, and continue polling
            console.log("Failed to connect, retrying in 5 seconds...");
        }

        // Wait for 5 seconds before retrying
        await new Promise(resolve => setTimeout(resolve, POLL_INTERVAL));
    }
}

export async function withRetry<T>(fn: () => Promise<T>, retryMessage = "retrying...", maxRetries = 20, retryDelay = 1000): Promise<T> {
    try {
        return await fn()
    } catch (err) {
        if (maxRetries <= 1) {
            throw err
        }
        console.error(retryMessage)
        await new Promise((resolve) => setTimeout(resolve, retryDelay))
        return withRetry(fn, retryMessage, maxRetries - 1, retryDelay)
    }
}
