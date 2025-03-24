import { ethers } from "hardhat";
require("dotenv").config();

export const defaultSigner = async () => (await ethers.getSigners())[0];
