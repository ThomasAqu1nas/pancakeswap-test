// scripts/testSwapAndLiquidity.ts
import { ethers } from "hardhat";
import { CustomRouter__factory, IERC20__factory } from "../typechain-types";
import { defaultSigner } from "./connection";
import deployedAddresses from "../ignition/deployments/chain-56/deployed_addresses.json";

async function main() {
  const signer = await defaultSigner();
  const routerAddress = deployedAddresses["CustomRouterModule#CustomRouter"];
  const tokenAddress = "0x55d398326f99059fF775485246999027B3197955";

  const CustomRouter = CustomRouter__factory.connect(routerAddress, signer);
  const Token = IERC20__factory.connect(tokenAddress, signer);

  const swapEthAmount = ethers.parseEther("0.1");
  const expectedTokenOut = ethers.parseUnits("100", 18);
  const tokenMin = ethers.parseUnits("95", 18);
  const ethMin = ethers.parseEther("0.09");
  const additionalEthForLiquidity = ethers.parseEther("0.2");
  const deadline = Math.floor(Date.now() / 1000) + 600;

  const totalETH = swapEthAmount + additionalEthForLiquidity;

  const initialTokenBalance = await Token.balanceOf(signer.address);

  try {
    await CustomRouter.swapThenAddLiquidity.staticCall(
      tokenAddress,
      swapEthAmount,
      expectedTokenOut,
      tokenMin,
      ethMin,
      additionalEthForLiquidity,
      deadline,
      { value: totalETH }
    );
    console.log("✅ Static call succeeded, proceeding with transaction");
  } catch (error: any) {
    console.error(
      "❌ Static call revert reason:",
      error.reason ?? error.message
    );
    process.exit(1);
  }

  const gasEstimate = await CustomRouter.swapThenAddLiquidity.estimateGas(
    tokenAddress,
    swapEthAmount,
    expectedTokenOut,
    tokenMin,
    ethMin,
    additionalEthForLiquidity,
    deadline,
    { value: totalETH }
  );

  const gasLimit = gasEstimate + gasEstimate / ethers.toBigInt(2);

  const tx = await CustomRouter.swapThenAddLiquidity(
    tokenAddress,
    swapEthAmount,
    expectedTokenOut,
    tokenMin,
    ethMin,
    additionalEthForLiquidity,
    deadline,
    { value: totalETH, gasLimit }
  );
  console.log("swapThenAddLiquidity transaction sent:", tx.hash);
  await tx.wait();

  const finalTokenBalance = await Token.balanceOf(signer.address);

  if (initialTokenBalance > finalTokenBalance) {
    console.log(
      "✅ swapThenAddLiquidity successful. Tokens used for liquidity."
    );
  } else {
    console.error(
      "❌ swapThenAddLiquidity failed or tokens were not used as expected."
    );
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
