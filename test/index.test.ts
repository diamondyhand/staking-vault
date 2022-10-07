import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { expect } from "chai";
import { deploySC, toWei } from "./helper";
import { StakingVault, ERC20Mock } from '../types'
import {
  UST_DECIMAL,
} from "./constants";

const timeTravel = async (seconds: number) => {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
};

describe("StakingVault Contract Test.", () => {
  let Tom: SignerWithAddress;
  let Jerry: SignerWithAddress;
  let Matin: SignerWithAddress;
  let Admin: SignerWithAddress;
  let StakingVault: StakingVault;
  let StakingToken: ERC20Mock;
  const dayTime = 24 * 3600;
  const UST100 = toWei(100, UST_DECIMAL);
  const UST200 = toWei(200, UST_DECIMAL);
  const UST1K = toWei(1000, UST_DECIMAL);
  const UST5K = toWei(5000, UST_DECIMAL);
  const UST10K = toWei(10000, UST_DECIMAL);
  const UST100K = toWei(100000, UST_DECIMAL);
  const UST200K = toWei(200000, UST_DECIMAL);
  const UST300K = toWei(300000, UST_DECIMAL);

  beforeEach(async () => {
    [Admin, Tom, Jerry, Matin] = await ethers.getSigners();
    StakingToken = <ERC20Mock>(
      await deploySC("ERC20Mock", [])
    )
    StakingVault = <StakingVault>(
      await deploySC("StakingVault", [StakingToken.address])
    )

  });

  describe("Test Start.", () => {
    it("lock increaseLock unLock", async () => {
      await StakingToken.mint(Tom.address, UST300K);
      await expect(StakingVault.connect(Tom).unLock(UST1K)).to.be.revertedWith("StakingVault: You must be create lock.");
      // lock expect
      await expect(StakingVault.connect(Tom).lock(0, 30 * dayTime)).to.be.revertedWith("amount is zero.");
      await expect(StakingVault.connect(Tom).lock(UST100, 30 * dayTime)).to.be.revertedWith("StakingVault: You must be approve.");
      await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
      await expect(StakingVault.connect(Tom).lock(UST100, 29 * dayTime)).to.be.revertedWith("StakingVault: period error.");
      // increase Lock expect
      await expect(StakingVault.connect(Tom).increaseLock(UST1K, 60 * dayTime)).to.be.revertedWith("StakingVault: You must be create lock.");
      await StakingVault.connect(Tom).lock(UST100, 30 * dayTime);
      await StakingVault.connect(Tom).claimRewards(Tom.address);

      await expect(StakingVault.connect(Tom).lock(UST100, 60 * dayTime)).to.be.revertedWith("StakingVault: You have already locked it.");
      // increase lock
      await StakingVault.connect(Tom).increaseLock(UST100, 30 * dayTime);
      await StakingVault.connect(Tom).increaseLock(UST100, 30 * dayTime);
      await StakingVault.connect(Tom).increaseLock(UST100, 30 * dayTime);
      // increase Lock expect
      await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
      await expect(StakingVault.connect(Tom).increaseLock(UST100, 3000 * dayTime)).to.be.revertedWith("StakingVault: increase period error.");

      await timeTravel(67 * dayTime);
      await expect(StakingVault.connect(Tom).unLock(UST100)).to.be.revertedWith("StakingVault: You can unlock after lock period.");
      await timeTravel(160 * dayTime);
      await expect(StakingVault.connect(Tom).increaseLock(UST100, 20 * dayTime)).to.be.revertedWith("StakingVault: Lock's deadline has expired.");
      // unLock
      await expect(StakingVault.connect(Tom).unLock(UST100K)).to.be.revertedWith("StakingVault: unlock amount error.");
      await StakingVault.connect(Tom).unLock(UST100);
      await StakingVault.connect(Tom).unLock(UST200);
      // increaseLock (Because locks deadline has expired, Period must be minimum one month.)
      await StakingToken.connect(Tom).approve(StakingVault.address, UST300K);
      // setRewardDistributor
      await StakingVault.setRewardDistributor(Tom.address);
      // notifyRewardAmount
      await StakingVault.connect(Tom).notifyRewardAmount(UST200K);
      await StakingToken.connect(Jerry).approve(StakingVault.address, UST100);
      await expect(StakingVault.connect(Jerry).notifyRewardAmount(UST100)).to.be.revertedWith("RewardDistributor can only call this function.");
      // ???????????????????????????????????
      await StakingToken.connect(Jerry).mint(Jerry.address, UST10K);
      await StakingToken.connect(Jerry).approve(StakingVault.address, UST1K);
      await StakingVault.connect(Jerry).lock(UST100, 30 * dayTime);
      await expect(StakingVault.lockFor(Jerry.address, UST100, 30 * dayTime)).to.be.revertedWith("StakingVault: You have already locked it.");
      await timeTravel(37 * dayTime);
      await StakingVault.connect(Jerry).unLock(UST100);

      console.log("Tom's amount is ", await StakingToken.balanceOf(Tom.address));
      const Reward = await StakingVault.getClaimableRewards(Tom.address);
      await console.log(`TomReward: ${ethers.utils.formatUnits(Reward, UST_DECIMAL)} $`);
    })

    it("pause, setRewardDistributor, notifyRewardAmount lockfor.", async () => {
      // pause function
      await StakingVault.setPause(true);
      await expect(StakingVault.connect(Tom).lock(0, 30 * dayTime)).to.be.revertedWith("Contract paused.");
      await StakingVault.setPause(false);
      // setRewardDistributor
      await StakingVault.setRewardDistributor(Jerry.address);
      await StakingToken.mint(Jerry.address, UST300K);
      await StakingToken.connect(Jerry).approve(StakingVault.address, UST300K);
      // notifyRewardAmount
      await StakingVault.connect(Jerry).notifyRewardAmount(UST200K);
      await StakingVault.connect(Jerry).lock(UST10K, 30 * dayTime);
      await StakingVault.connect(Jerry).increaseLock(UST5K, 10 * dayTime);
      await StakingVault.connect(Jerry).increaseLock(UST5K, 10 * dayTime);
      await timeTravel(37 * dayTime);

      const JerryReward = await StakingVault.getClaimableRewards(Jerry.address);
      console.log(`JerryReward: ${ethers.utils.formatUnits(JerryReward, UST_DECIMAL)} $`);
      // lockfor
      await StakingToken.mint(Jerry.address, UST200K);
      await StakingToken.connect(Jerry).approve(StakingVault.address, UST200K);
      // claimReward
      await expect(StakingVault.connect(Tom).claimRewards(Jerry.address)).to.be.revertedWith("StakingVault: Not permission.");
      const JerryReward1 = await StakingVault.getClaimableRewards(Jerry.address);
      console.log(`JerryReward1: ${ethers.utils.formatUnits(JerryReward1, UST_DECIMAL)} $`);
      // await timeTravel(20 * dayTime);
      await StakingVault.connect(Jerry).compound(Jerry.address, UST100);
      await expect(StakingVault.connect(Jerry).compound(Jerry.address, UST10K)).to.be.revertedWith("StakingVault: Not Enough compound rewards.");
      await timeTravel(17 * dayTime);
      const JerryReward2 = await StakingVault.getClaimableRewards(Jerry.address);
      console.log(`JerryReward2: ${ethers.utils.formatUnits(JerryReward2, UST_DECIMAL)} $`);
      // compound
      await expect(StakingVault.connect(Jerry).compound(Jerry.address, UST100)).to.be.revertedWith("StakingVault: Lock's deadline has expired.");
      await expect(StakingVault.connect(Jerry).compound(Tom.address, UST100)).to.be.revertedWith("StakingVault: Not permission.");
      await expect(StakingVault.connect(Admin).lockFor(Jerry.address, UST10K, 30 * dayTime)).to.be.revertedWith("StakingVault: You have already locked it.");

      // lockFor
      await StakingToken.mint(Matin.address, UST300K);
      await StakingToken.connect(Matin).approve(StakingVault.address, UST300K);
      await expect(StakingVault.connect(Admin).lockFor(Matin.address, UST10K, 3000 * dayTime)).to.be.revertedWith("StakingVault: period error.");
      await StakingVault.connect(Admin).lockFor(Matin.address, UST10K, 30 * dayTime);
      await timeTravel(17 * dayTime);
      await StakingVault.connect(Matin).claimRewards(Matin.address);
    });
  });
})