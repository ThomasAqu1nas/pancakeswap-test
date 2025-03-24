import { ethers, network } from "hardhat";

export async function setNativeBalance(
  targetAddress: string,
  amountInWei: string
) {
  await network.provider.send("anvil_setBalance", [targetAddress, amountInWei]);
  const balance = await ethers.provider.getBalance(targetAddress);
  console.log(
    `Новый баланс ${targetAddress}:`,
    ethers.formatEther(balance),
    "ETH"
  );
}
