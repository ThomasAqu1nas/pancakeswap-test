import { ethers } from "hardhat";
import { IERC20__factory, IPancakeRouter__factory } from "../typechain-types";

async function main() {
  const [signer] = await ethers.getSigners();

  const pancakeRouterAddress = "0x10ED43C718714eb63d5aA57B78B54704E256024E"; // PancakeRouter (BSC)
  const pancakeRouter = IPancakeRouter__factory.connect(
    pancakeRouterAddress,
    signer
  );

  const tokenAddress = "0x524bC91Dc82d6b90EF29F76A3ECAaBAffFD490Bc";
  const token = IERC20__factory.connect(tokenAddress, signer);

  const amountToken = ethers.parseUnits("10000", 6);
  const amountETH = ethers.parseEther("10");

  await token.approve(pancakeRouterAddress, amountToken);

  const tx = await pancakeRouter.addLiquidityETH(
    tokenAddress,
    amountToken,
    0,
    0,
    signer.address,
    Math.floor(Date.now() / 1000) + 600,
    { value: amountETH }
  );

  await tx.wait();

  console.log("✅ Ликвидность успешно добавлена.");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
