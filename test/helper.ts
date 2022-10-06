import { ethers } from "hardhat";
import { BigNumber } from "ethers";

export const deploySC = async (scName: string, params: any) => {
  const contract = await ethers.getContractFactory(scName);
  const SC = await contract.deploy(...params);
  await SC.deployed();
  return SC;
};

export const toWei = (amount: number, decimal: number) => {
  let newAmount: BigNumber;
  newAmount = BigNumber.from(amount);
  return newAmount.mul(BigNumber.from("10").pow(decimal));
};

export const fromWei = (amount: BigNumber, decimal: number) => {
  return amount.div(BigNumber.from("10").pow(decimal));
};
