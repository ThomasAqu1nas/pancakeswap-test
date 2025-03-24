// scripts/testSwap.ts
import { ethers } from "hardhat";
import {
  CustomRouter__factory,
  IERC20,
  IERC20__factory,
} from "../typechain-types";
import { defaultSigner } from "./connection";
import deployedAddresses from "../ignition/deployments/chain-56/deployed_addresses.json";

async function main() {
  const signer = await defaultSigner();
  const routerAddress = deployedAddresses["CustomRouterModule#CustomRouter"];
  const tokenAddress = "0x55d398326f99059fF775485246999027B3197955";

  const CustomRouter = CustomRouter__factory.connect(routerAddress, signer);
  const Token = await IERC20__factory.connect(tokenAddress, signer);

  const swapEthAmount = ethers.parseEther("0.1");
  const expectedTokenOut = ethers.parseUnits("100", 18);
  const deadline = Math.floor(Date.now() / 1000) + 600;

  const initialTokenBalance = await Token.balanceOf(signer.address);
  console.log("Initial Token Balance: ", initialTokenBalance);
  try {
    await CustomRouter.swapEthForExactTokensExternal.staticCall(
      expectedTokenOut,
      tokenAddress,
      swapEthAmount,
      deadline,
      { value: swapEthAmount }
    );
    console.log("✅ Static call success, swap can proceed");
  } catch (error: any) {
    console.error(
      "❌ Static call revert reason:",
      error.reason ?? error.message
    );
    process.exit(1);
  }

  const gasEstimate =
    await CustomRouter.swapEthForExactTokensExternal.estimateGas(
      expectedTokenOut,
      tokenAddress,
      swapEthAmount,
      deadline,
      { value: swapEthAmount }
    );

  const gasLimit = gasEstimate + gasEstimate / ethers.toBigInt(2);

  const tx = await CustomRouter.swapEthForExactTokensExternal(
    expectedTokenOut,
    tokenAddress,
    swapEthAmount,
    deadline,
    { value: swapEthAmount, gasLimit }
  );

  console.log("Swap transaction sent:", tx.hash);
  await tx.wait();

  const finalTokenBalance = await Token.balanceOf(signer.address);
  const tokenReceived = finalTokenBalance - initialTokenBalance;

  if (tokenReceived >= expectedTokenOut) {
    console.log(
      "✅ Swap successful, tokens received:",
      ethers.formatUnits(tokenReceived, 18)
    );
  } else {
    console.error("❌ Swap failed or tokens insufficient");
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
