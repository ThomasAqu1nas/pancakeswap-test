import { ethers } from "hardhat";
import { IERC20__factory } from "../typechain-types";

async function main() {
  const [signer] = await ethers.getSigners();

  const tokenAddress = "0x524bC91Dc82d6b90EF29F76A3ECAaBAffFD490Bc"; // USDT (BSC mainnet)
  const tokenHolder = "0x9ade1c17d25246c405604344f89E8F23F8c1c632";

  await ethers.provider.send("anvil_impersonateAccount", [tokenHolder]);
  const impersonatedSigner = await ethers.getSigner(tokenHolder);

  const token = IERC20__factory.connect(tokenAddress, impersonatedSigner);

  const amount = ethers.parseUnits("10000", 6); // 10k
  const tx = await token.transfer(signer.address, amount);
  await tx.wait();

  console.log("✅ Переведено 100000 USDT на аккаунт:", signer.address);

  await ethers.provider.send("anvil_stopImpersonatingAccount", [tokenHolder]);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
