/* eslint-disable @typescript-eslint/no-explicit-any */

import {
    ethers,
    keccak256,
    Interface,
    Provider,
    TransactionReceipt,
    isHexString,
    id,
    AbiCoder,
    Signer,
    ParamType,
    EventFragment,
    Result
} from "ethers"
import {Deployer__factory} from "../generated"

export const factoryAddress = "0x8464135c8F25Da09e49BC8782676a84730C318bC"
export const factoryBytecode = Deployer__factory.bytecode
export const factoryAbi = Deployer__factory.abi

export const buildBytecode = (
    constructorTypes: readonly ParamType[],
    constructorArgs: readonly any[],
    contractBytecode: string,
) =>
    `${contractBytecode}${encodeParams(constructorTypes, constructorArgs).slice(
        2,
    )}`

export const buildCreate2Address = (saltHex: string, byteCode: string) => {
    return `0x${keccak256(
        `0x${["ff", factoryAddress, saltHex, keccak256(byteCode)]
            .map((x) => x.replace(/0x/, ""))
            .join("")}`,
    )
        .slice(-40)}`.toLowerCase()
}

export const saltToHex = (salt: string | number) => {
    salt = salt.toString()
    if (isHexString(salt)) {
        return salt
    }

    return id(salt)
}

export const encodeParams = (dataTypes: readonly ParamType[] | readonly string[], data: readonly any[]): string => {
    const abiCoder = AbiCoder.defaultAbiCoder()
    return abiCoder.encode(dataTypes, data)
}

// Deploy contract using Create2
export async function deployContract({
                                         salt,
                                         contractBytecode,
                                         constructorTypes = [],
                                         constructorArgs = [],
                                         signer,
                                     }: {
    salt: string | number
    contractBytecode: string
    constructorTypes?: readonly ParamType[]
    constructorArgs?: readonly any[]
    signer: Signer
}) {
    const saltHex = saltToHex(salt)
    const factory = new ethers.Contract(factoryAddress, factoryAbi, signer)
    const bytecode = buildBytecode(
        constructorTypes,
        constructorArgs,
        contractBytecode,
    )

    const tx = await factory.deploy(saltHex, bytecode)
    const receipt = await tx.wait(1)

    return {
        txHash: receipt.transactionHash,
        address: buildCreate2Address(saltHex, bytecode),
        receipt,
    }
}

// Calculate create2 address of a contract.
export function getCreate2Address({
                                      salt,
                                      contractBytecode,
                                      constructorTypes = [],
                                      constructorArgs = []
                                  }: {
    salt: string | number
    contractBytecode: string
    constructorTypes?: readonly ParamType[]
    constructorArgs?: readonly any[]
}) {
    return buildCreate2Address(
        saltToHex(salt),
        buildBytecode(constructorTypes, constructorArgs, contractBytecode),
    )
}

// Determine if a given contract is deployed.
export async function isDeployed(address: string, provider: Provider) {
    const code = await provider.getCode(address)
    return code.slice(2).length > 0
}

// Deploy create2 factory for local development.
export async function deployFactory(signer: Signer) {
    const Factory = new ethers.ContractFactory(
        factoryAbi,
        factoryBytecode,
        signer,
    )
    const factory = await Factory.deploy()
    await factory.waitForDeployment()
    const deployedAt = await factory.getAddress()
    if (deployedAt !== factoryAddress) {
        throw new Error("factory is deployed to an unexpected address!")
    }
    return deployedAt
}

// extracts an event log of a given type from a transaction receipt that matches the address provided
export function extractLogs<T extends Interface, E extends EventFragment>(iface: T, receipt: TransactionReceipt, contractAddress: string, event: E): Array<Result> {
    return receipt.logs
        .filter(log => log.address.toLowerCase() === contractAddress.toLowerCase())
        .map(log => iface.decodeEventLog(event, log.data, log.topics))
}

// returns the first instance of an event log from a transaction receipt that matches the address provided
export function extractSingleLog<T extends Interface, E extends EventFragment>(iface: T, receipt: TransactionReceipt, contractAddress: string, event: E): Result {
    const events = extractLogs(iface, receipt, contractAddress, event)
    if (events.length === 0) {
        throw Error(`contract at ${contractAddress} didn't emit the ${event.name} event`)
    }
    return events[0]
}