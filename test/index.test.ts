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
  const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

  beforeEach(async () => {
    [Admin, Tom, Jerry, Matin] = await ethers.getSigners();
    StakingToken = <ERC20Mock>(
      await deploySC("ERC20Mock", [])
    )
    const stakingVault = await ethers.getContractFactory("StakingVault");
    await expect(stakingVault.deploy(ZERO_ADDRESS)).to.be.revertedWith("StakingVault: address must not be zero address.");

    StakingVault = <StakingVault>(
      await deploySC("StakingVault", [StakingToken.address])
    )
    await StakingToken.mint(Tom.address, UST300K);
    await StakingToken.mint(Jerry.address, UST300K);
  });

  describe("Test Start.", () => {
    describe("Lock function.", () => {
      it("revert if lock error.(amount, approve, period error.)", async () => {
        await expect(StakingVault.connect(Tom).lock(0, 30 * dayTime)).to.be.revertedWith("StakingVault: amount zero.");
        await expect(StakingVault.connect(Tom).lock(UST100, 30 * dayTime)).to.be.revertedWith("StakingVault: You must be approve.");
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await expect(StakingVault.connect(Tom).lock(UST100, 29 * dayTime)).to.be.revertedWith("StakingVault: period error.");
      })

      it("revert if lock is created.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await StakingVault.connect(Tom).lock(UST100, 30 * dayTime);
        await expect(StakingVault.connect(Tom).lock(UST100, 39 * dayTime)).to.be.revertedWith("StakingVault: You have already locked it.");
      })

      it("lock is successful.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await StakingVault.connect(Tom).lock(UST100, 30 * dayTime);
      })
    })

    describe("increaseLock function.", () => {
      it("revert if lock is not created.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await expect(StakingVault.connect(Tom).increaseLock(UST1K, 60 * dayTime)).to.be.revertedWith("StakingVault: You must be create lock.");
        await StakingVault.connect(Tom).lock(UST100, 30 * dayTime);
      });
      it("revert if param period is overflow.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await StakingVault.connect(Tom).lock(UST100, 30 * dayTime);
        await expect(StakingVault.connect(Tom).increaseLock(UST100, 2000 * dayTime)).to.be.revertedWith("StakingVault: increase period error.");
      })
      it("revert if lock period is expired.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await StakingVault.connect(Tom).lock(UST100, 30 * dayTime);
        await timeTravel(67 * dayTime);
        await expect(StakingVault.connect(Tom).increaseLock(UST100, 20 * dayTime)).to.be.revertedWith("StakingVault: Lock's deadline has expired.");
      })
      it("increase successful.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await StakingVault.connect(Tom).lock(UST100, 30 * dayTime);
        await StakingVault.connect(Tom).increaseLock(UST100, 20 * dayTime);
      })
    })

    describe("unLock function.", () => {
      it("revert if lock is not created.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await expect(StakingVault.connect(Tom).unLock(UST1K)).to.be.revertedWith("StakingVault: You must be create lock.");
      });

      it("revert if lock period is not expired.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await StakingVault.connect(Tom).lock(UST100, 30 * dayTime);
        await expect(StakingVault.connect(Tom).unLock(UST100)).to.be.revertedWith("StakingVault: You can unlock after lock period.");
      })
      it("revert if unlock amount is bigger than locked amount.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await StakingVault.connect(Tom).lock(UST100, 30 * dayTime);
        await timeTravel(67 * dayTime);
        await expect(StakingVault.connect(Tom).unLock(UST200)).to.be.revertedWith("StakingVault: unlock amount error.");
      })
      it("unLock is successful.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await StakingVault.connect(Tom).lock(UST200, 30 * dayTime);
        await timeTravel(100 * dayTime);
        await StakingVault.connect(Tom).unLock(UST100);
        await StakingVault.connect(Tom).unLock(UST100);
      })
    })

    describe("lockFor function.", () => {
      it("lockFor is successful.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await StakingVault.connect(Admin).lockFor(Tom.address, UST1K, 30 * dayTime);
      });
    })


    describe("setRewardDistributor function.", () => {
      it("setRewardDistributor is successful.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await StakingVault.connect(Admin).setRewardDistributor(Tom.address);
      });
    })

    describe("setPause function.", () => {
      it("setPause is successful.", async () => {
        await StakingVault.connect(Admin).setPause(true);
        await StakingVault.connect(Admin).setPause(false);
      });
    })

    describe("notifyRewardAmount function.", () => {
      it("revert if user is not RewardDistributor.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await StakingVault.connect(Admin).setRewardDistributor(Tom.address);
        await expect(StakingVault.connect(Admin).notifyRewardAmount(UST1K)).to.be.revertedWith("RewardDistributor can only call this function.");
      });

      it("notifyRewardAmount is successful.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
        await StakingVault.connect(Admin).setRewardDistributor(Tom.address);
        await StakingVault.connect(Tom).notifyRewardAmount(UST1K);
      });
    })


    describe("compound and claim function.", () => {
      it("revert if user is not msg.sender.", async () => {
        await StakingToken.connect(Jerry).approve(StakingVault.address, UST300K);
        await StakingVault.connect(Jerry).lock(UST300K, 30 * dayTime);
        await timeTravel(20 * dayTime);
        await expect(StakingVault.connect(Jerry).compound(Tom.address, UST100)).to.be.revertedWith("StakingVault: Not permission.");
      })
      it("revert if Lock's deadline has expired.", async () => {
        await StakingToken.connect(Jerry).approve(StakingVault.address, UST300K);
        await StakingVault.connect(Jerry).lock(UST300K, 30 * dayTime);
        await timeTravel(40 * dayTime);
        await expect(StakingVault.connect(Jerry).compound(Jerry.address, UST100)).to.be.revertedWith("StakingVault: Lock's deadline has expired.");
      })
      it("revert if reward is not enough.", async () => {
        await StakingToken.connect(Jerry).approve(StakingVault.address, UST300K);
        await StakingVault.connect(Jerry).lock(UST300K, 30 * dayTime);
        await timeTravel(20 * dayTime);
        await expect(StakingVault.connect(Jerry).compound(Jerry.address, UST100)).to.be.revertedWith("StakingVault: Not Enough compound rewards.");
      })

      it("compound is successful.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST300K);
        await StakingVault.connect(Admin).setRewardDistributor(Tom.address);
        await StakingVault.connect(Tom).notifyRewardAmount(UST1K);

        await StakingVault.connect(Tom).lock(UST200K, 300 * dayTime);
        await timeTravel(200 * dayTime);
        const TomReward = await StakingVault.getClaimableRewards(Tom.address);
        console.log(`TomReward: ${ethers.utils.formatUnits(TomReward, UST_DECIMAL)} $`);

        await StakingVault.connect(Tom).compound(Tom.address, UST100);
      });
    })

    describe("claimRewards function.", () => {
      it("revert if user is not msg.sender.", async () => {
        await expect(StakingVault.connect(Admin).claimRewards(Tom.address)).to.be.revertedWith("StakingVault: Not permission.");
      });

      it("reward is zero.", async () => {
        await StakingVault.connect(Tom).claimRewards(Tom.address);
      });

      it("reward is not zero.", async () => {
        await StakingToken.connect(Tom).approve(StakingVault.address, UST300K);
        await StakingVault.connect(Admin).setRewardDistributor(Tom.address);
        await StakingVault.connect(Tom).notifyRewardAmount(UST1K);

        await StakingVault.connect(Tom).lock(UST200K, 300 * dayTime);
        await timeTravel(200 * dayTime);
        await StakingVault.connect(Tom).claimRewards(Tom.address);
      });

    })

  });
})