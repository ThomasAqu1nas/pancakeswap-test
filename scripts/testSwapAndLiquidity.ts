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

  // Создаем инстанс для токена пары
  const lpTokenABI = ["function balanceOf(address) view returns (uint256)"];
  const lpToken = new ethers.Contract(pairAddress, lpTokenABI, signer);

  const initialLPBalance = await lpToken.balanceOf(signer.address);
  console.log("Initial LP token balance:", initialLPBalance.toString());

  // Для упрощенной функции swapThenAddLiquiditySimple ожидается, что пользователь отправляет 2 BNB:
  // 1 BNB для свапа в USDT и 1 BNB для ликвидности
  const totalETH = ethers.parseEther("2");

  const deadline = Math.floor(Date.now() / 1000) + 600;

  try {
    await CustomRouter.swapThenAddLiquiditySimple.staticCall(
      tokenAddress,
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

  const gasEstimate = await CustomRouter.swapThenAddLiquiditySimple.estimateGas(
    tokenAddress,
    deadline,
    { value: totalETH }
  );

  const gasLimit = gasEstimate + gasEstimate / ethers.toBigInt(2);

  const tx = await CustomRouter.swapThenAddLiquiditySimple(
    tokenAddress,
    deadline,
    { value: totalETH, gasLimit }
  );
  console.log("swapThenAddLiquiditySimple transaction sent:", tx.hash);
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
