import {AbstractSigner, AddressLike} from "ethers"
import {
    BlocklockSender__factory,
    BlocklockSignatureScheme__factory,
    BlsBn254,
    DecryptionSender__factory,
    deployContract,
    getCreate2Address,
    isDeployed,
    SignatureSchemeAddressProvider__factory,
} from "@randamu/bls-bn254-js/src"
import {G2} from "mcl-wasm"

const salt = 2345
export const BLOCKLOCK_SCHEME_ID = "BN254-BLS-BLOCKLOCK";

/**
 * Deploy the signature scheme address provider contract
 */
export async function deploySchemeProvider(signer: AbstractSigner): Promise<string> {
    if (!signer.provider) {
        throw Error("`Signer` must have a valid RPC provider")
    }
    const owner = await signer.getAddress()
    const creationParams = {
        salt,
        contractBytecode: SignatureSchemeAddressProvider__factory.bytecode,
        constructorTypes: SignatureSchemeAddressProvider__factory.createInterface().deploy.inputs,
        constructorArgs: [owner],
    }
    const computedAddr = getCreate2Address(creationParams)

    if (await isDeployed(computedAddr, signer.provider)) {
        console.log("signature scheme addresses provider contract already deployed")
        return computedAddr
    }
    const result = await deployContract({...creationParams, signer})
    return result.address
}

/**
 * Deploy the blocklock signature scheme contract, and register it in the scheme provider
 */
export async function deployBlocklockScheme(signer: AbstractSigner): Promise<string> {
    if (!signer.provider) {
        throw Error("`Signer` must have a valid RPC provider")
    }
    const creationParams = {
        salt,
        contractBytecode: BlocklockSignatureScheme__factory.bytecode,
        constructorTypes: BlocklockSignatureScheme__factory.createInterface().deploy.inputs,
        constructorArgs: []
    }
    const computedAddr = getCreate2Address(creationParams)

    if (await isDeployed(computedAddr, signer.provider)) {
        console.log('signature scheme addresses provider contract already deployed')
        return computedAddr
    }
    const result = await deployContract({...creationParams, signer})
    return result.address
}

/**
 * Deploy the decryption sender contract
 */
export async function deployDecryptionSender(bls: BlsBn254, signer: AbstractSigner, blsPublicKey: G2, schemeProvider: AddressLike): Promise<string> {
    if (!signer.provider) {
        throw Error("`deployDecryptionSender` must have a valid RPC provider")
    }
    const [x1, x2, y1, y2] = bls.serialiseG2Point(blsPublicKey)
    const owner = await signer.getAddress()

    const creationParams = {
        salt,
        contractBytecode: DecryptionSender__factory.bytecode,
        constructorTypes: DecryptionSender__factory.createInterface().deploy.inputs,
        constructorArgs: [[x1, x2], [y1, y2], owner, schemeProvider],
    }
    const computedAddr = getCreate2Address(creationParams)

    if (await isDeployed(computedAddr, signer.provider)) {
        console.log('signature sender contract already deployed')
        return computedAddr
    }
    const result = await deployContract({...creationParams, signer})
    return result.address
}

/**
 * Deploy the blocklock contract
 */
export async function deployBlocklock(signer: AbstractSigner, decryptionSenderContractAddr: AddressLike): Promise<string> {
    if (!signer.provider) {
        throw Error("`SignatureRequests` must have a valid RPC provider")
    }
    const creationParams = {
        salt,
        contractBytecode: BlocklockSender__factory.bytecode,
        constructorTypes: BlocklockSender__factory.createInterface().deploy.inputs,
        constructorArgs: [decryptionSenderContractAddr],
    }
    const computedAddr = getCreate2Address(creationParams)

    if (await isDeployed(computedAddr, signer.provider)) {
        return computedAddr
    }
    const result = await deployContract({...creationParams, signer})
    return result.address
}
