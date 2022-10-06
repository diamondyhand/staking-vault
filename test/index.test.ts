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
    describe("Main Functions Start.", () => {
      it("lock increaselock unlock", async () => {
        // await StakingToken.mint(Tom.address, 10000);
        // await StakingToken.mint(Jerry.address, 10000);
        // await StakingVault.setPause(true);
        // await expect(StakingVault.connect(Tom).lock(0, 30 * dayTime)).to.be.revertedWith("Contract paused.");
        // await StakingVault.setPause(false);
        // await expect(StakingVault.connect(Tom).unlock(1000, 30 * dayTime)).to.be.revertedWith("StakingVault: You must be create lock.");
        // await expect(StakingVault.connect(Tom).lock(0, 30 * dayTime)).to.be.revertedWith("amount is zero.");
        // await expect(StakingVault.connect(Tom).lock(100, 30 * dayTime)).to.be.revertedWith("StakingVault: You must be approve.");
        // await expect(StakingVault.connect(Tom).lock(100, 29 * dayTime)).to.be.revertedWith("StakingVault: period error.");

        // await StakingToken.connect(Tom).approve(StakingVault.address, 1100);
        // await expect(StakingVault.connect(Tom).increaselock(1000, 60 * dayTime)).to.be.revertedWith("StakingVault: You must be create lock.");
        // await StakingVault.connect(Tom).lock(100, 30 * dayTime);
        // await expect(StakingVault.connect(Tom).lock(1000, 60 * dayTime)).to.be.revertedWith("StakingVault: You have already locked it.");
        // await StakingVault.connect(Tom).increaselock(1000, 30 * dayTime);

        // timeTravel(50 * dayTime);
        // await expect(StakingVault.connect(Tom).unlock(1000, 20 * dayTime)).to.be.revertedWith("StakingVault: You can unlock after lock period.");
        // timeTravel(17 * dayTime);
        // await StakingVault.connect(Tom).unlock(1000, 20 * dayTime);
        // await expect(StakingVault.connect(Tom).unlock(1000, 60 * dayTime)).to.be.revertedWith("StakingVault: You can't unlock.");
      })

      it("lock increaselock unlock", async () => {
        await StakingVault.setRewardDistributor(Jerry.address);
        await StakingToken.mint(Jerry.address, toWei(3 * 10 ** 5, UST_DECIMAL));
        await StakingToken.connect(Jerry).approve(StakingVault.address, toWei(3 * 10 ** 5, UST_DECIMAL));
        await StakingVault.connect(Jerry).notifyRewardAmount(toWei(2 * 10 ** 5, UST_DECIMAL));

        await StakingVault.connect(Jerry).lock(toWei(10000, UST_DECIMAL), 30 * dayTime);
        await timeTravel(37 * dayTime);
        const JerryReward = await StakingVault.getClaimableRewards(Jerry.address);
        console.log(`JerryReward: ${ethers.utils.formatUnits(JerryReward, UST_DECIMAL)} $`);
        const Vault = await StakingToken.balanceOf(StakingVault.address);
        console.log(`Vault: ${ethers.utils.formatUnits(Vault, UST_DECIMAL)} $`);
      })
    });
  });
})