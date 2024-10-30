import {describe, it, expect} from "@jest/globals"
import {Wallet} from "ethers"
import {Blocklock} from "../src"

describe("blocklock", () => {
  it("class can be constructed", () => {
    const w = new Wallet("0x5cb3c5ba25c91d84ef5dabf4152e909795074f9958b091b010644cb9c30e3203")
    const r = new Blocklock("0x0", w)
    expect(r).not.toEqual(null)
  })
})