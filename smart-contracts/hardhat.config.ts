import { HardhatUserConfig } from "hardhat/config";
// foundry support
import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: "0.8.28",
};

export default config;