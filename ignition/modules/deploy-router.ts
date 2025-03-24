// tasks/deploy-router.ts
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

//address _factory, address _WBNB, address _pancakeRouter
module.exports = buildModule("CustomRouterModule", (m) => {
  const myContract = m.contract("CustomRouter", [
    "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73",
    "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
    "0x10ED43C718714eb63d5aA57B78B54704E256024E",
  ]);
  return { myContract };
});
