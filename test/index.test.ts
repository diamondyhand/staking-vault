import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { deploySC, toWei, fromWei } from "./helper";
import { StakingVault, ERC20Mock } from '../types'
import {
  MAX_DECIMAL,
  UST_DECIMAL,
} from "./constants";

const timeTravel = async (seconds: number) => {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
};

describe("StakingVault Contract Test.", () => {
  let Tom: SignerWithAddress;
  let Jerry: SignerWithAddress;
  let Admin: SignerWithAddress;
  let StakingVault: StakingVault;
  let StakingToken: ERC20Mock;
  const dayTime = 24 * 3600;
  const UST100 = toWei(100, UST_DECIMAL);
  const UST200 = toWei(200, UST_DECIMAL);
  const UST500 = toWei(500, UST_DECIMAL);
  const UST1K = toWei(1000, UST_DECIMAL);
  const UST10K = toWei(10000, UST_DECIMAL);
  const UST100K = toWei(100000, UST_DECIMAL);
  const UST200K = toWei(200000, UST_DECIMAL);


  beforeEach(async () => {
    [Admin, Tom, Jerry] = await ethers.getSigners();
    StakingToken = <ERC20Mock>(
      await deploySC("ERC20Mock", ["UST", "UST"])
    )
    StakingVault = <StakingVault>(
      await deploySC("StakingVault", [StakingToken.address])
    )

  });

  describe("Test Start.", () => {

    it("lock increaselock unlock", async () => {
      await StakingToken.mint(Tom.address, UST1K);
      await expect(StakingVault.connect(Tom).unlock(UST1K, 30 * dayTime)).to.be.revertedWith("StakingVault: You must be create lock.");
      await expect(StakingVault.connect(Tom).lock(0, 30 * dayTime)).to.be.revertedWith("amount is zero.");
      await expect(StakingVault.connect(Tom).lock(UST100, 30 * dayTime)).to.be.revertedWith("StakingVault: You must be approve.");
      await expect(StakingVault.connect(Tom).lock(UST100, 29 * dayTime)).to.be.revertedWith("StakingVault: period error.");

      await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
      await expect(StakingVault.connect(Tom).increaselock(UST1K, 60 * dayTime)).to.be.revertedWith("StakingVault: You must be create lock.");
      await StakingVault.connect(Tom).lock(UST100, 30 * dayTime);
      await expect(StakingVault.connect(Tom).lock(UST100, 60 * dayTime)).to.be.revertedWith("StakingVault: You have already locked it.");
      await StakingVault.connect(Tom).increaselock(UST100, 30 * dayTime);
      // await StakingVault.connect(Tom).increaselock(UST100, 3000 * dayTime);
      await expect(StakingVault.connect(Tom).increaselock(UST100, 3000 * dayTime)).to.be.revertedWith("StakingVault: increase period error.");

      await timeTravel(50 * dayTime);
      await expect(StakingVault.connect(Tom).unlock(UST100, 20 * dayTime)).to.be.revertedWith("StakingVault: You can unlock after lock period.");
      await timeTravel(17 * dayTime);
      await StakingVault.connect(Tom).unlock(UST100, 20 * dayTime);
      const Reward = await StakingVault.getClaimableRewards(Tom.address);
      await console.log(`TomReward: ${ethers.utils.formatUnits(Reward, UST_DECIMAL)} $`);
    })

    it("pause, setRewardDistributor, notifyRewardAmount.", async () => {
      // pause function
      await StakingVault.setPause(true);
      await expect(StakingVault.connect(Tom).lock(0, 30 * dayTime)).to.be.revertedWith("Contract paused.");
      await StakingVault.setPause(false);
      // setRewardDistributor
      await StakingVault.setRewardDistributor(Jerry.address);
      await StakingToken.mint(Jerry.address, UST200K);
      await StakingToken.connect(Jerry).approve(StakingVault.address, UST200K);
      // notifyRewardAmount
      await StakingVault.connect(Jerry).notifyRewardAmount(UST100K);
      await StakingVault.connect(Jerry).lock(UST10K, 30 * dayTime);
      await timeTravel(37 * dayTime);
      const JerryReward = await StakingVault.getClaimableRewards(Jerry.address);
      console.log(`JerryReward: ${ethers.utils.formatUnits(JerryReward, UST_DECIMAL)} $`);

      const Vault = await StakingToken.balanceOf(StakingVault.address);
      console.log(`Vault: ${ethers.utils.formatUnits(Vault, UST_DECIMAL)} $`);
    });
  });
})