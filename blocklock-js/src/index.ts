import { BaseContract, LogDescription, Provider, Signer, TransactionReceipt } from "ethers"
import {
    type BlocklockSender,
    BlocklockSender__factory
} from "./generated"
import { encrypt_towards_identity_g1, Ciphertext, G2, decrypt_towards_identity_g1, G1, serializeCiphertext, deserializeCiphertext } from '@randamu/bls-bn254-js/src'

export class Blocklock {
    private blocklockSender: BlocklockSender

    constructor(blocklockSenderContractAddr: string, provider: Signer | Provider) {
        this.blocklockSender = BlocklockSender__factory.connect(blocklockSenderContractAddr, provider)
    }

    /**
     * Request a blocklock decryption at block number blockHeight.
     * @param blockHeight time at which the decryption should key should be released
     * @param ciphertext encrypted message to store on chain
     * @returns blocklock request id as a string
     */
    async requestBlocklock(blockHeight: bigint, ciphertext: Uint8Array): Promise<string> {
        // Request a blocklock at blockHeight
        const tx = await this.blocklockSender.requestBlocklock(blockHeight, ciphertext)
        const receipt = await tx.wait(1)
        if (!receipt) {
            throw new Error("transaction has not been mined")
        }

        const logs = parseLogs(receipt, this.blocklockSender, "BlocklockRequested")
        if (logs.length === 0) {
            throw Error("`requestBlocklock` didn't emit the expected log")
        }

        const [requestID,] = logs[0].args
        return requestID
    }

    /**
     * Fetch the details of a blocklock request, decryption key / signature excluded.
     * @param sRequestID blocklock request id
     * @returns details of the blocklock request, undefined if not found
     */
    async fetchBlocklockRequest(sRequestID: string): Promise<BlocklockRequest | undefined> {
        const requestID = BigInt(sRequestID)

        // Query BlocklockRequested event with correct requestID
        const callbackFilter = this.blocklockSender.filters.BlocklockRequested(requestID)
        const events = await this.blocklockSender.queryFilter(callbackFilter)

        // We get exactly one result if it was successful
        if (events.length == 0) {
            return undefined;
        } else if (events.length > 1) {
            throw new Error("BlocklockRequested filter returned more than one result")
        }
        return {
            id: events[0].args.requestID.toString(),
            blockHeight: events[0].args.blockHeight,
            ciphertext: Buffer.from(events[0].args.ciphertext.slice(2), 'hex')
        }
    }

    /**
     * Fetch all blocklock requests, decryption keys / signatures excluded.
     * @returns a map with the details of each blocklock request
     */
    async fetchAllBlocklockRequests(): Promise<Map<string, BlocklockRequest>> {
        const requestFilter = this.blocklockSender.filters.BlocklockRequested()
        const requests = await this.blocklockSender.queryFilter(requestFilter)

        return new Map(Array.from(
            requests.map((event) => {
                const requestID = event.args.requestID.toString()

                return [requestID, {
                    id: requestID,
                    blockHeight: event.args.blockHeight,
                    ciphertext: Buffer.from(event.args.ciphertext.slice(2), 'hex'),
                }]
            })
        ))
    }

    /**
     * Fetch the status of a blocklock request, including the decryption key / signature if available.
     * @param sRequestID blocklock request id
     * @returns details of the blocklock request, undefined if not found
     */
    async fetchBlocklockStatus(sRequestID: string): Promise<BlocklockStatus | undefined> {
        const requestID = BigInt(sRequestID)
        const callbackFilter = this.blocklockSender.filters.BlocklockCallbackSuccess(requestID)
        const events = await this.blocklockSender.queryFilter(callbackFilter)

        // We get exactly one result if it was successful
        if (events.length == 0) {
            // No callback yet, query the BlocklockRequested events instead
            return await this.fetchBlocklockRequest(sRequestID)
        } else if (events.length > 1) {
            throw new Error("BlocklockCallbackSuccess filter returned more than one result")
        }

        return {
            id: events[0].args.requestID.toString(),
            blockHeight: events[0].args.blockHeight,
            signature: events[0].args.signature,
            ciphertext: Buffer.from(events[0].args.ciphertext.slice(2), 'hex'),
        }
    }

    /**
     * Encrypt a message that can be decrypted once a certain blockHeight is reached.
     * @param message plaintext to encrypt
     * @param blockHeight time at which the decryption key should be released
     * @param pk public key of the scheme
     * @returns encrypted message
     */
    encrypt(message: Uint8Array, blockHeight: bigint, pk: G2): Ciphertext {
        const identity = blockHeightToBEBytes(blockHeight)
        const ciphertext = encrypt_towards_identity_g1(message, identity, pk)

        return ciphertext
    }

    /**
     * Decrypt a ciphertext using a decryption key.
     * @param ciphertext the ciphertext to decrypt
     * @param key decryption key
     * @returns plaintext
     */
    decrypt(ciphertext: Ciphertext, key: G1): Uint8Array {
        return decrypt_towards_identity_g1(ciphertext, key)
    }

    /**
     * Encrypt a message that can be decrypted once a certain blockHeight is reached.
     * @param message plaintext to encrypt
     * @param blockHeight time at which the decryption key should be released
     * @param pk public key of the scheme
     * @returns the identifier of the blocklock request, and the ciphertext
     */
    async encryptAndRegister(message: Uint8Array, blockHeight: bigint, pk: G2): Promise<{ id: string, ct: Ciphertext }> {
        const identity = blockHeightToBEBytes(blockHeight)
        const ct = encrypt_towards_identity_g1(message, identity, pk)

        const id = await this.requestBlocklock(blockHeight, serializeCiphertext(ct))
        return {
            id: id.toString(),
            ct,
        }
    }

    /**
     * Try to decrypt a ciphertext with a specific blocklock id.
     * @param sRequestID blocklock id of the ciphertext to decrypt
     * @returns the plaintext if the decryption key is available, undefined otherwise
     */
    async decryptWithId(sRequestID: string): Promise<Uint8Array | undefined> {
        const status = await this.fetchBlocklockStatus(sRequestID)
        if (!status) {
            throw new Error("cannot find a request with this identifier")
        }

        // Signature has not been delivered yet, return
        if (!status.signature) {
            return
        }

        // Deserialize ciphertext
        const ct = deserializeCiphertext(status.ciphertext)

        // Decrypt the ciphertext with the provided signature
        const x = BigInt('0x' + status.signature.slice(2, 66))
        const y = BigInt('0x' + status.signature.slice(66, 130))
        return decrypt_towards_identity_g1(ct, { x, y })
    }
}

export type BlocklockRequest = {
    id: string,
    blockHeight: bigint,
    ciphertext: Uint8Array,
}

export type BlocklockStatus = BlocklockRequest & {
    signature?: string,
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

function parseLogs(receipt: TransactionReceipt, contract: BaseContract, eventName: string): Array<LogDescription> {
    return receipt.logs
        .map(log => {
            try {
                return contract.interface.parseLog(log)
            } catch {
                return null
            }
        })
        .filter(log => log !== null)
        .filter(log => log?.name === eventName)
}
