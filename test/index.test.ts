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
    [Admin, Tom, Jerry] = await ethers.getSigners();
    StakingToken = <ERC20Mock>(
      await deploySC("ERC20Mock", [])
    )
    StakingVault = <StakingVault>(
      await deploySC("StakingVault", [StakingToken.address])
    )

  });

  describe("Test Start.", () => {
    it("lock increaselock unlock", async () => {
      await StakingToken.mint(Tom.address, UST300K);
      await expect(StakingVault.connect(Tom).unlock(UST1K)).to.be.revertedWith("StakingVault: You must be create lock.");
      // lock expect
      await expect(StakingVault.connect(Tom).lock(0, 30 * dayTime)).to.be.revertedWith("amount is zero.");
      await expect(StakingVault.connect(Tom).lock(UST100, 30 * dayTime)).to.be.revertedWith("StakingVault: You must be approve.");
      await expect(StakingVault.connect(Tom).lock(UST100, 29 * dayTime)).to.be.revertedWith("StakingVault: period error.");

      await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
      // increase Lock expect
      await expect(StakingVault.connect(Tom).increaselock(UST1K, 60 * dayTime)).to.be.revertedWith("StakingVault: You must be create lock.");
      await StakingVault.connect(Tom).lock(UST100, 30 * dayTime);
      await StakingVault.connect(Tom).claimRewards(Tom.address);

      await expect(StakingVault.connect(Tom).lock(UST100, 60 * dayTime)).to.be.revertedWith("StakingVault: You have already locked it.");
      // increase lock
      await StakingVault.connect(Tom).increaselock(UST100, 30 * dayTime);
      await StakingVault.connect(Tom).increaselock(UST100, 30 * dayTime);
      await StakingVault.connect(Tom).increaselock(UST100, 30 * dayTime);
      // increase Lock expect
      await expect(StakingVault.connect(Tom).increaselock(UST100, 3000 * dayTime)).to.be.revertedWith("StakingVault: increase period error.");

      await timeTravel(67 * dayTime);
      await expect(StakingVault.connect(Tom).unlock(UST100)).to.be.revertedWith("StakingVault: You can unlock after lock period.");
      await timeTravel(160 * dayTime);
      await expect(StakingVault.connect(Tom).increaselock(UST100, 20 * dayTime)).to.be.revertedWith("StakingVault: Lock's deadline has expired.");
      await expect(StakingVault.connect(Tom).unlock(UST10K)).to.be.revertedWith("StakingVault: unlock amount error.");
      // unlock
      await StakingVault.connect(Tom).unlock(UST200);
      await StakingVault.connect(Tom).unlock(UST200);
      // increaselock (Because locks deadline has expired, Period must be minimum one month.)
      await StakingToken.connect(Tom).approve(StakingVault.address, UST300K);
      // setRewardDistributor
      await StakingVault.setRewardDistributor(Tom.address);
      // notifyRewardAmount
      await StakingVault.connect(Tom).notifyRewardAmount(UST200K);
      await expect(StakingVault.connect(Jerry).notifyRewardAmount(UST200K)).to.be.revertedWith("RewardDistributor can only call this function.");
      await StakingVault.connect(Tom).lock(UST10K, 30 * dayTime);
      await StakingVault.connect(Tom).increaselock(UST5K, 30 * dayTime);
      await StakingVault.connect(Tom).increaselock(UST10K, 30 * dayTime);
      await timeTravel(37 * dayTime);

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
      await StakingVault.connect(Jerry).increaselock(UST5K, 10 * dayTime);
      await StakingVault.connect(Jerry).increaselock(UST5K, 10 * dayTime);
      await timeTravel(37 * dayTime);

      const JerryReward = await StakingVault.getClaimableRewards(Jerry.address);
      console.log(`JerryReward: ${ethers.utils.formatUnits(JerryReward, UST_DECIMAL)} $`);
      // lockfor
      await StakingToken.mint(Jerry.address, UST200K);
      await StakingToken.connect(Jerry).approve(StakingVault.address, UST200K);
      await StakingVault.connect(Admin).lockFor(Jerry.address, UST10K, 30 * dayTime);

      // claimReward
      await StakingVault.connect(Jerry).claimRewards(Jerry.address);
      await expect(StakingVault.connect(Tom).claimRewards(Jerry.address)).to.be.revertedWith("StakingVault: Not permission.");
      const JerryReward1 = await StakingVault.getClaimableRewards(Jerry.address);
      console.log(`JerryReward1 (claim after): ${ethers.utils.formatUnits(JerryReward1, UST_DECIMAL)} $`);
      await timeTravel(20 * dayTime);
      await StakingVault.connect(Jerry).compound(Jerry.address, UST100);
      await expect(StakingVault.connect(Jerry).compound(Jerry.address, UST10K)).to.be.revertedWith("StakingVault: Not Enough compound rewards.");
      await timeTravel(17 * dayTime);
      const JerryReward2 = await StakingVault.getClaimableRewards(Jerry.address);
      console.log(`JerryReward2: ${ethers.utils.formatUnits(JerryReward2, UST_DECIMAL)} $`);
      // compound
      await expect(StakingVault.connect(Jerry).compound(Jerry.address, UST100)).to.be.revertedWith("StakingVault: Lock's deadline has expired.");
    });
  });
})