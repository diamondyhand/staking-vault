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
    const UST10 = toWei(10, UST_DECIMAL);
    const UST100 = toWei(100, UST_DECIMAL);
    const UST200 = toWei(200, UST_DECIMAL);
    const UST250 = toWei(250, UST_DECIMAL);
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
            it("revert if lock error.(amount, period error.)", async () => {
                await expect(StakingVault.connect(Tom).lock(0, 30)).to.be.revertedWith("StakingVault: amount zero.");
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await expect(StakingVault.connect(Tom).lock(UST100, 29)).to.be.revertedWith("StakingVault: period error.");
            })

            it("lock is successful.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await StakingVault.connect(Tom).lock(UST100, 30);
                // variable
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(100, UST_DECIMAL).toBigInt(),
                );
            })
        })

        describe("increaseLock function.", () => {
            it("revert if lock is not created.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await expect(StakingVault.connect(Tom).increaseLock(UST1K, 60, 1)).to.be.revertedWith("StakingVault: lockId not exist.");
            });

            it("revert if param period is overflow.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await StakingVault.connect(Tom).lock(UST100, 30);

                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(100, UST_DECIMAL).toBigInt(),
                );
                await expect(StakingVault.connect(Tom).increaseLock(UST100, 2000, 1)).to.be.revertedWith("StakingVault: increase period error.");
            })

            it("revert if lock period is expired.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await StakingVault.connect(Tom).lock(UST100, 30);
                await timeTravel(67 * dayTime);
                await expect(StakingVault.connect(Tom).increaseLock(UST100, 20, 1)).to.be.revertedWith("StakingVault: Lock's deadline has expired.");
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(100, UST_DECIMAL).toBigInt(),
                );
            })

            it("increase successful.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await StakingVault.connect(Tom).lock(UST100, 30);
                await StakingVault.connect(Tom).increaseLock(UST100, 20, 1);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(200, UST_DECIMAL).toBigInt(),
                );
            })
        })

        describe("unLock function.", () => {
            it("revert if lock is not created.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await expect(StakingVault.connect(Tom).unLock(UST1K, 1, false)).to.be.revertedWith("StakingVault: lockId not exist.");
            });

            it("revert if lock period is not expired.(lockId != 0)", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await StakingVault.connect(Tom).lock(UST100, 30);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(100, UST_DECIMAL).toBigInt(),
                );
                await expect(StakingVault.connect(Tom).unLock(UST100, 1, false)).to.be.revertedWith("StakingVault: You can unlock after lock period.");
            })

            it("revert if unlock amount is bigger than locked amount.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await StakingVault.connect(Tom).lock(UST100, 30);

                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(100, UST_DECIMAL).toBigInt(),
                );

                await timeTravel(67 * dayTime);
                await expect(StakingVault.connect(Tom).unLock(UST200, 1, false)).to.be.revertedWith("StakingVault: unlock amount error.");
            })


            it("revert if unlock all amount is bigger than locked amount.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST300K);
                await StakingVault.connect(Tom).addRewards(UST100);

                await StakingVault.connect(Tom).lock(UST100, 30);
                await StakingVault.connect(Tom).lock(UST100, 30);
                await StakingVault.connect(Tom).lock(UST100, 30);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(400, UST_DECIMAL).toBigInt(),
                );
                await timeTravel(60 * dayTime);
                await expect(StakingVault.connect(Tom).unLock(UST1K, 0, false)).to.be.revertedWith("StakingVault: all unlock amount error.");
            })

            it("revert if unlock all amount is bigger than locked amount.(updateReward)", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await StakingVault.connect(Tom).lock(UST100, 30);
                await StakingVault.connect(Tom).lock(UST100, 70);
                await StakingVault.connect(Tom).lock(UST100, 30);
                await StakingVault.connect(Tom).lock(UST100, 30);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(400, UST_DECIMAL).toBigInt(),
                );
                await timeTravel(67 * dayTime);

                await StakingVault.connect(Tom).unLock(UST250, 0, true);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(150, UST_DECIMAL).toBigInt(),
                );

                /// unlock false
                await StakingVault.connect(Tom).lock(UST100, 30);
                await StakingVault.connect(Tom).lock(UST100, 70);
                await StakingVault.connect(Tom).lock(UST100, 30);
                await StakingVault.connect(Tom).lock(UST100, 30);
                await timeTravel(67 * dayTime);

                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(550, UST_DECIMAL).toBigInt(),
                );
                await StakingVault.connect(Tom).unLock(UST250, 0, false);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(300, UST_DECIMAL).toBigInt(),
                );
            })


            it("unLock is successful.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await StakingVault.connect(Tom).lock(UST200, 30);

                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(200, UST_DECIMAL).toBigInt(),
                );
                await timeTravel(100 * dayTime);
                await StakingVault.connect(Tom).unLock(UST100, 1, false);
                await StakingVault.connect(Tom).unLock(UST100, 1, false);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(0, UST_DECIMAL).toBigInt(),
                );
            })
        })

        describe("lockFor function.", () => {
            it("lockFor is successful.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await StakingVault.connect(Admin).lockFor(Tom.address, UST1K, 30);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(1000, UST_DECIMAL).toBigInt(),
                );
            });
        })

        describe("setPause function.", () => {
            it("setPause is successful.", async () => {
                await StakingVault.connect(Admin).setPause(true);
                await StakingVault.connect(Admin).setPause(false);
            });
        })

        describe("addRewards function.", () => {
            it("addRewards is successful.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST1K);
                await StakingVault.connect(Tom).addRewards(UST1K);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(1000, UST_DECIMAL).toBigInt(),
                );
            });
        })


        describe("compound and claim function.", async () => {
            it("revert if user is not msg.sender and lock is not exist.", async () => {
                await StakingToken.connect(Jerry).approve(StakingVault.address, UST300K);
                await StakingVault.connect(Jerry).lock(UST300K, 30);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(3 * 10 ** 5, UST_DECIMAL).toBigInt(),
                );
                await timeTravel(20 * dayTime);
                // await expect(StakingVault.connect(Jerry).compound(UST100, 1)).to.be.revertedWith("StakingVault: Not permission.");
                await expect(StakingVault.connect(Jerry).compound(UST100, 0)).to.be.revertedWith("StakingVault: lockId not exist.");
            })
            it("revert if Lock's deadline has expired.", async () => {
                await StakingToken.connect(Jerry).approve(StakingVault.address, UST300K);
                await StakingVault.connect(Jerry).lock(UST300K, 30);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(3 * 10 ** 5, UST_DECIMAL).toBigInt(),
                );
                await timeTravel(40 * dayTime);
                await expect(StakingVault.connect(Jerry).compound(UST100, 1)).to.be.revertedWith("StakingVault: Lock's deadline has expired.");
            })

            it("revert if reward is not enough.", async () => {
                await StakingToken.connect(Jerry).approve(StakingVault.address, UST300K);
                await StakingVault.connect(Jerry).lock(UST300K, 30);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(3 * 10 ** 5, UST_DECIMAL).toBigInt(),
                );
                await timeTravel(20 * dayTime);
                await expect(StakingVault.connect(Jerry).compound(UST100, 1)).to.be.revertedWith("StakingVault: Not Enough compound rewards.");
            })

            it("compound is successful.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST300K);
                await StakingVault.connect(Tom).addRewards(UST100);

                await StakingVault.connect(Tom).lock(UST200K, 600);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(2 * 10 ** 5 + 100, UST_DECIMAL).toBigInt(),
                );
                await timeTravel(530 * dayTime);
                const TomReward = await StakingVault.getClaimableRewards(Tom.address, 1);
                const TotalReward = await StakingVault.getClaimableRewards(Tom.address, 0);
                console.log(`TomReward: ${ethers.utils.formatUnits(TomReward, UST_DECIMAL)} $`);
                // revert if getClaimableRewards function lockId not exist.
                await expect(StakingVault.getClaimableRewards(Tom.address, 3)).to.be.revertedWith("StakingVault: lockId not exist.");

                await StakingVault.connect(Tom).compound(UST10, 1);
            });
        })

        describe("claimRewards function.", () => {
            it("revert if lockId not exist.", async () => {
                await expect(StakingVault.connect(Admin).claimRewards(2)).to.be.revertedWith("StakingVault: lockId not exist.");
            });

            it("claimRewards successful.", async () => {
                await StakingToken.connect(Tom).approve(StakingVault.address, UST300K);
                await StakingVault.connect(Tom).addRewards(UST100);

                await StakingVault.connect(Tom).lock(UST200K, 300);
                expect(await StakingToken.balanceOf(StakingVault.address)).to.be.equal(
                    toWei(2 * 10 ** 5 + 100, UST_DECIMAL).toBigInt(),
                );
                await timeTravel(230 * dayTime);
                await StakingVault.connect(Tom).claimRewards(1);
                await StakingVault.connect(Tom).claimRewards(0);
            });
        })
    });
})