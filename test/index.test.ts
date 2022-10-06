import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { deploySC, toWei, fromWei } from "./helper";
import { StakingVault, ERC20Mock } from '../types'

describe("StakingVault Contract Test.", () => {
  let Tom: SignerWithAddress;
  let Jerry: SignerWithAddress;
  let Admin: SignerWithAddress;
  let StakingVault: StakingVault;
  let StakingToken: ERC20Mock;
  beforeEach(async () => {
    [Admin, Tom, Jerry] = await ethers.getSigners();
    StakingToken = <ERC20Mock>(
      await deploySC("ERC20Mock", ["USD", "USD"])
    )
    StakingVault = <StakingVault>(
      await deploySC("StakingVault", [StakingToken.address])
    )

  });

  describe("Test Start.", () => {
    describe("Main Functions Start.", () => {
      it("Add", async () => {
        console.log("stakingToken is ", StakingToken.address);
        await StakingVault.setPause(true);
        await StakingVault.setPause(false);

      })
    });
  });
})