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

  const factoryAddress = await CustomRouter.factory();
  const WBNBAddress = await CustomRouter.WBNB();

  const factoryABI = [
    "function getPair(address tokenA, address tokenB) view returns (address pair)",
  ];
  const pancakeFactory = new ethers.Contract(
    factoryAddress,
    factoryABI,
    signer
  );
  const pairAddress = await pancakeFactory.getPair(WBNBAddress, tokenAddress);

  if (!pairAddress || pairAddress === ethers.ZeroAddress) {
    console.error("❌ Pair for given tokens does not exist.");
    process.exit(1);
  }

  const lpTokenABI = ["function balanceOf(address) view returns (uint256)"];
  const lpToken = new ethers.Contract(pairAddress, lpTokenABI, signer);

  const initialLPBalance = await lpToken.balanceOf(signer.address);
  console.log("Initial LP token balance:", initialLPBalance.toString());

  const swapEthAmount = ethers.parseEther("1");
  const liquidityEthAmount = ethers.parseEther("1");
  const minTokensOut = ethers.parseUnits("0.1", 18); // Минимум токенов, для примера

  const totalETH = swapEthAmount + liquidityEthAmount;

  const deadline = Math.floor(Date.now() / 1000) + 600;

  try {
    await CustomRouter.swapThenAddLiquidity.staticCall(
      tokenAddress,
      swapEthAmount,
      liquidityEthAmount,
      minTokensOut,
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
    liquidityEthAmount,
    minTokensOut,
    deadline,
    { value: totalETH }
  );

  const gasLimit = gasEstimate + gasEstimate / ethers.toBigInt(2);

  const tx = await CustomRouter.swapThenAddLiquidity(
    tokenAddress,
    swapEthAmount,
    liquidityEthAmount,
    minTokensOut,
    deadline,
    { value: totalETH, gasLimit }
  );
  console.log("swapThenAddLiquidity transaction sent:", tx.hash);
  await tx.wait();

  const finalLPBalance = await lpToken.balanceOf(signer.address);
  console.log("Final LP token balance:", finalLPBalance.toString());

  if (finalLPBalance > initialLPBalance) {
    console.log("✅ swapThenAddLiquidity successful. LP tokens received.");
  } else {
    console.error("❌ swapThenAddLiquidity failed or no LP tokens received.");
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
