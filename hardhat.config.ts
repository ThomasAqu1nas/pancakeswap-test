import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
require("dotenv").config();

const config: HardhatUserConfig = {
  solidity: "0.8.28",
  networks: {
    anvil: {
      url: "http://127.0.0.1:8545",
      chainId: 56,
      accounts: [process.env.DEFAULT_SIGNER_PRIVATE_KEY as string],
    },
  },
  defaultNetwork: "anvil",
};

export default config;
