const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SimpleAuction Deployment", function () {
  const durationBlocks = 10;
  const reservePrice = ethers.parseEther("0.1"); // Converted to wei;
  const highestBidPaymentWindowBlocks = 5;
  const SCHEME_ID = "BN254-BLS-BLOCKLOCK";

  it("Should deploy all contracts and verify SimpleAuction initialization", async function () {
    // Deploy SignatureSchemeAddressProvider
    const SignatureSchemeAddressProvider = await ethers.getContractFactory("SignatureSchemeAddressProvider");
    const sigAddrProvider = await SignatureSchemeAddressProvider.deploy();
    await sigAddrProvider.waitForDeployment();
    expect(await sigAddrProvider.getAddress()).to.properAddress;

    // Deploy BlocklockSignatureScheme
    const BlocklockSignatureScheme = await ethers.getContractFactory("BlocklockSignatureScheme");
    const tlockScheme = await BlocklockSignatureScheme.deploy();
    await tlockScheme.waitForDeployment();
    expect(await tlockScheme.getAddress()).to.properAddress;

    // Register BlocklockSignatureScheme in SignatureSchemeAddressProvider
    await sigAddrProvider.updateSignatureScheme(SCHEME_ID, await tlockScheme.getAddress());
    const registeredScheme = await sigAddrProvider.getSignatureSchemeAddress(SCHEME_ID);
    const registeredScemeInstance = await ethers.getContractAt("BlocklockSignatureScheme", registeredScheme);
    expect(await registeredScemeInstance.getAddress()).to.equal(await tlockScheme.getAddress());

    // Deploy SignatureSender with a valid BLS public key
    const publicKey = [
      "5830776630907064314539321794930804939504088708094156564482220995414892723476",
      "5981666596598098661213039413382287967543823405050279744471706544297945483736",
      "13781030701232382820909590458778060376018466655784590456583140552266805740306",
      "7030038015738296159400582602579364380546678709006876788396713702549817484274",
    ];

    const SignatureSender = await ethers.getContractFactory("SignatureSender");
    const sigsender = await SignatureSender.deploy(
      [publicKey[0], publicKey[1]],
      [publicKey[2], publicKey[3]],
      await sigAddrProvider.getAddress(),
    );
    await sigsender.waitForDeployment();
    expect(await sigsender.getAddress()).to.properAddress;

    // Deploy BlocklockSender
    const BlocklockSender = await ethers.getContractFactory("BlocklockSender");
    const tlock = await BlocklockSender.deploy(await sigsender.getAddress());
    await tlock.waitForDeployment();
    expect(await tlock.getAddress()).to.properAddress;

    // Deploy SimpleAuction
    const SimpleAuction = await ethers.getContractFactory("SimpleAuction");
    const simpleAuction = await SimpleAuction.deploy(
      durationBlocks,
      reservePrice,
      highestBidPaymentWindowBlocks,
      await tlock.getAddress(),
    );
    await simpleAuction.waitForDeployment();
    expect(await simpleAuction.getAddress()).to.properAddress;

    // Verify SimpleAuction initialization parameters
    const actualEndBlock = await simpleAuction.auctionEndBlock();
    const actualReservePrice = await simpleAuction.reservePrice();
    const actualHighestBidPaymentDeadlineBlock = await simpleAuction.highestBidPaymentDeadlineBlock();
    const actualBlocklockSender = await simpleAuction.timelock();

    expect(actualEndBlock).to.be.gt(0);
    expect(actualReservePrice).to.equal(reservePrice);
    expect(actualHighestBidPaymentDeadlineBlock).to.gt(0);
    expect(actualBlocklockSender).to.equal(await tlock.getAddress());
  });
});
