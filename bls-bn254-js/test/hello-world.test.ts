import {describe, it, expect} from "@jest/globals"
import {BlsBn254} from "../src/index"

describe("hello", () => {
  it("world", async () => {
    const bls = await BlsBn254.create()
    const keypair = bls.createKeyPair()
    expect(keypair.pubKey).not.toBeNull()
  })
})