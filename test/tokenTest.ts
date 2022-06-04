import chai, { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { BigNumber, Wallet } from "ethers";
import { parseEther, hexlify } from "ethers/lib/utils";
import { MockProvider, solidity } from "ethereum-waffle";
import { ecsign } from 'ethereumjs-util'

import { Token, Manager } from "../typechain-types";
import { deployContracts, getPermitDigest } from "./utils/helpers";

chai.use(solidity)

describe("Token Test", function () {
    let manager: Manager;
    let token: Token;
    let deployer: SignerWithAddress;
    let sender: SignerWithAddress;
    let receiver: SignerWithAddress;
    let nonAdmin: SignerWithAddress;
    let brokeBoi: SignerWithAddress;

    const provider = new MockProvider({ ganacheOptions: {
        hardfork: 'istanbul',
        mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
        gasLimit: 9999999
    }})
    const TWO_ETH = parseEther("2.0")
    
    beforeEach(async () => {
        [ deployer, sender, receiver, nonAdmin, brokeBoi ] = await ethers.getSigners();

        const contracts = (await deployContracts(deployer));
        token = contracts.token;
        manager = contracts.manager;
    });

    describe("Decimals",async () => {
        it("should return the correct decimals", async () => {
            expect(await token.decimals()).to.be.eq(6);
        });
    });

    describe("Access Control", async () => {
        it("should not let non-admins grant roles", async () => {
            const adminRole = await manager.DEFAULT_ADMIN_ROLE()
            await expect(
                manager.connect(nonAdmin).grantRole(
                    adminRole, nonAdmin.address
                )
            ).to.be.reverted

            expect(await manager.hasRole(adminRole, nonAdmin.address)
            ).to.be.eq(false)
        });

        it("should allow admins to grant roles", async () => {
            const minterRole = await manager.MINTER_ROLE()

            await expect(
                manager.connect(deployer).grantRole(minterRole, nonAdmin.address)
            ).to.not.be.reverted
            expect(
                await manager.hasRole(minterRole, nonAdmin.address)
            ).to.be.eq(true)

            await expect(
                token.connect(nonAdmin).mint(nonAdmin.address, TWO_ETH)
            ).to.not.be.reverted
            expect(
                await token.balanceOf(nonAdmin.address)
            ).to.be.eq(TWO_ETH);
        });

        it("should be able to revoke a role", async () => {
            const adminRole = await manager.GOVERNOR_ROLE()
            const minterRole = await manager.MINTER_ROLE()

            await expect(
                manager.connect(deployer).revokeRole(adminRole, deployer.address)
            ).to.not.be.reverted
            expect(
                await manager.connect(deployer).hasRole(adminRole, deployer.address)
            ).to.be.eq(false)

            await expect(
                manager.connect(deployer).grantRole(adminRole, nonAdmin.address)
            ).to.be.reverted
            await expect(
                manager.connect(deployer).grantRole(adminRole, nonAdmin.address)
            ).to.be.reverted
            await expect(
                manager.connect(deployer).grantRole(minterRole, nonAdmin.address)
            ).to.be.reverted
        })
    })

    describe("Mint", async () => {
        it("should not mint tokens to caller if called by unauthorised Minter", async () => {
            await expect(token.connect(sender).mint(sender.address, TWO_ETH)
            ).to.be.reverted
            expect(await token.balanceOf(sender.address)
            ).to.be.eq(parseEther("0.0"))
        });
        it("should mint tokens to caller if called by a Minter", async () => {
            await expect(token.connect(deployer).mint(receiver.address, TWO_ETH)
            ).to.not.be.reverted

            expect(await token.balanceOf(receiver.address)
            ).to.be.eq(TWO_ETH)
        });
        it("should mint tokens to an address if called by a Minter only", async () => {
            await expect(token.connect(deployer).mint(nonAdmin.address, TWO_ETH)
            ).to.not.be.reverted

            await expect(token.connect(sender).mint(nonAdmin.address, TWO_ETH)
            ).to.be.reverted
        });
    });

    describe("Burn", async () => {
        it("should not burn tokens to caller if called by an unautheorised Burner", async () => {
            await token.connect(deployer).mint(receiver.address, TWO_ETH.add(parseEther("1.0")))

            await expect(token.connect(receiver).burn(receiver.address, TWO_ETH)
            ).to.be.reverted
            expect(await token.balanceOf(receiver.address)
            ).to.be.eq(parseEther("3.0"))
        });
        it("should burn tokens to caller if called by a Burner", async () => {
            await token.connect(deployer).mint(deployer.address, TWO_ETH)
            expect(await token.balanceOf(deployer.address)).to.be.eq(TWO_ETH)

            await expect(token.connect(deployer).burn(deployer.address, parseEther("1.0"))
            ).to.not.be.reverted

            expect(await token.balanceOf(deployer.address)
            ).to.be.eq(parseEther("1.0"))
        });
        it("should burn tokens to an address if called by a Burner only", async () => {
            await token.connect(deployer).mint(receiver.address, TWO_ETH.add(parseEther("1.0")))
            expect(await token.balanceOf(receiver.address)).to.be.eq(parseEther("3.0"))

            await expect(token.connect(deployer).burn(receiver.address, parseEther("1.0"))
            ).to.not.be.reverted

            expect(await token.balanceOf(receiver.address)
            ).to.be.eq(parseEther("2.0"))
        });
    });

    describe("Transfer", async () => {
        const ONE_ETH = parseEther("1.0");

        beforeEach(async () => {
            [ sender, receiver ].forEach(async (signer) => {
                await token.connect(deployer).mint(signer.address, TWO_ETH)
            });
        });

        it("should not allow transfer if spender doesn't have funds", async () => {
            await expect(
                token.connect(brokeBoi).transfer(receiver.address, ONE_ETH)
            ).to.be.revertedWith("ERC20: transfer amount exceeds balance")

            expect(
                await token.balanceOf(brokeBoi.address)
            ).to.be.eq(0)
            expect(
                await token.balanceOf(receiver.address)
            ).to.be.eq(TWO_ETH)
        });

        it("should revert if the spender isn't allowed to transfer on token owner's behalf", async () => {
            await expect(
                token.connect(brokeBoi).transferFrom(sender.address, brokeBoi.address, ONE_ETH)
            ).to.be.revertedWith("ERC20: insufficient allowance")

            expect(
                await token.balanceOf(brokeBoi.address)
            ).to.be.eq(0)
        });

        it("transfer: should transfer funds if the sender has funds", async () => {
            await expect(
                token.connect(sender).transfer(receiver.address, ONE_ETH)
            ).to.not.be.reverted
        });

        it("transferFrom: should transfer funds if the caller is allowed to, and spender has funds", async () => {
            await expect(
                token.connect(sender).approve(receiver.address, ONE_ETH)
            ).to.not.be.reverted

            await expect(
                token.connect(receiver).transferFrom(sender.address, receiver.address, ONE_ETH)
            ).to.not.be.reverted
        });
    })

    describe("Permits", async () => {
        let admin: Wallet | SignerWithAddress
        let permitted: Wallet | SignerWithAddress
        let notPermitted: Wallet | SignerWithAddress

        let nonce: BigNumber
        let deadline: number;
        let digest: string;

        beforeEach(async () => {
            [ admin, permitted, notPermitted ] = provider.getWallets();
            
            nonce = await token.nonces(permitted.address)
            deadline = (await ethers.provider.getBlock("latest")).timestamp + (14 * 10);

            [ admin, permitted, notPermitted, sender, receiver ].forEach(async (wallet) => {
                await token.connect(deployer).mint(wallet.address, parseEther("3.0"))
            });


            digest = await getPermitDigest(
                token,
                { owner: admin.address, spender: permitted.address, amount: TWO_ETH },
                nonce, BigNumber.from(deadline)
            )
        })

        it("should permit a signer to do a transfer", async () => {
            const { v, r, s } = ecsign(
                Buffer.from(digest.slice(2), 'hex'),
                Buffer.from((admin as Wallet).privateKey.slice(2), 'hex')
            )

            await expect(
                token.permit(
                    admin.address, permitted.address, TWO_ETH, deadline,
                    v, hexlify(r), hexlify(s))
                ).to.not.be.reverted
            
            expect(await token.allowance(admin.address, permitted.address)).to.eq(TWO_ETH)
        });

        it("should not allow a token transfer if not permited by admin", async () => {
            digest = await getPermitDigest(
                token,
                { owner: admin.address, spender: notPermitted.address, amount: TWO_ETH },
                nonce, BigNumber.from(deadline)
            )

            const { v, r, s } = ecsign(
                Buffer.from(digest.slice(2), 'hex'),
                Buffer.from((notPermitted as Wallet).privateKey.slice(2), 'hex')
            )

            const permitPayload = {
                nonce: nonce,
                deadline: deadline,
                v: v,
                r: r,
                s: s
            }

            await expect(token.tranferFromUsingPermit(
                admin.address, notPermitted.address, TWO_ETH, permitPayload
            )).to.be.revertedWith("{token_name}: INVALID_SIGNATURE")

            expect(await token.balanceOf(notPermitted.address)).to.be.eq(parseEther("3.0"))
        });

        it("should minimize gas cost", async () => {
            const { v, r, s } = ecsign(
                Buffer.from(digest.slice(2), 'hex'),
                Buffer.from((admin as Wallet).privateKey.slice(2), 'hex')
            )

            const permitPayload = {
                nonce: nonce,
                deadline: deadline,
                v: v,
                r: r,
                s: s
            }

            expect(await token.balanceOf(permitted.address)).to.be.eq(parseEther("3.0"))

            let tx = await token.tranferFromUsingPermit(
                    admin.address, permitted.address, TWO_ETH,
                    permitPayload
                )
            const permittedTransferReceipt = tx.wait()
            
            tx = await token.connect(sender).approve(receiver.address, TWO_ETH)
            const approvalRecipt = tx.wait()
            
            tx = await token.connect(receiver).transferFrom(sender.address, receiver.address, TWO_ETH)
            const transferReceipt = tx.wait()
            
            const gasUsedToPermitTransfer = (await permittedTransferReceipt).gasUsed
            
            const gasUsedToApprove = (await approvalRecipt).gasUsed
            expect(await token.balanceOf(permitted.address)
            ).to.be.eq(TWO_ETH.add(parseEther("3.0")))
                
            const gasUsedToTransfer = (await transferReceipt).gasUsed
            const approveAndTransferGas = gasUsedToApprove.add(gasUsedToTransfer).toNumber()
            expect(await token.balanceOf(receiver.address)
            ).to.be.eq(TWO_ETH.add(parseEther("3.0")))

            expect(gasUsedToPermitTransfer.toNumber()
                ).to.be.lessThan(
                    approveAndTransferGas
            )
        });
    });
});
