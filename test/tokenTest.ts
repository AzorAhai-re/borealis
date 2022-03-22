import chai, { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { BigNumber, Wallet } from "ethers";
import { parseEther, hexlify } from "ethers/lib/utils";
import { MockProvider, solidity } from "ethereum-waffle";
import { ecsign } from 'ethereumjs-util'

import { Token } from "../typechain-types";
import { deployToken, getPermitDigest, get_raw_signature } from "./utils/helpers";

chai.use(solidity)

describe("Token Test", function () {
    let token: Token;
    let deployer: SignerWithAddress;
    let sender: SignerWithAddress;
    let receiver: SignerWithAddress;
    let nonAdmin: SignerWithAddress;

    const provider = new MockProvider({ ganacheOptions: {
        hardfork: 'istanbul',
        mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
        gasLimit: 9999999
    }})
    const TWO_ETH = parseEther("2.0")
    
    beforeEach(async () => {
        [ deployer, sender, receiver, nonAdmin ] = await ethers.getSigners()

        token = await deployToken(deployer)
    });

    describe("Access Control", async () => {
        it("should not let non-admins grant roles",async () => {
            const adminRole = await token.DEFAULT_ADMIN_ROLE()
            await expect(
                token.connect(nonAdmin).grantRole(
                    adminRole, nonAdmin.address
                )
            ).to.be.reverted

            expect(await token.hasRole(adminRole, nonAdmin.address)
            ).to.be.eq(false)
        });

        it("should allow admins to grant roles", async () => {
            const minterRole = await token.MINTER_ROLE()

            await expect(
                token.connect(deployer).grantRole(minterRole, nonAdmin.address)
            ).to.not.be.reverted
            expect(
                await token.hasRole(minterRole, nonAdmin.address)
            ).to.be.eq(true)

            await expect(
                token.connect(nonAdmin).mint(nonAdmin.address, TWO_ETH)
            ).to.not.be.reverted
            expect(
                await token.balanceOf(nonAdmin.address)
            ).to.be.eq(TWO_ETH);
        });

        it("should be able to revoke a role",async () => {
            const adminRole = await token.DEFAULT_ADMIN_ROLE()
            const minterRole = await token.MINTER_ROLE()

            await expect(
                token.connect(deployer).revokeRole(adminRole, deployer.address)
            ).to.not.be.reverted
            expect(
                await token.connect(deployer).hasRole(adminRole, deployer.address)
            ).to.be.eq(false)

            await expect(
                token.connect(deployer).grantRole(adminRole, nonAdmin.address)
            ).to.be.reverted
            await expect(
                token.connect(deployer).grantRole(adminRole, nonAdmin.address)
            ).to.be.reverted
            await expect(
                token.connect(deployer).grantRole(minterRole, nonAdmin.address)
            ).to.be.reverted
        })
    })

    describe("Mint", async () => {
        it("should not mint if called by unauthorised minter",async () => {
            await expect(token.connect(sender).mint(sender.address, TWO_ETH)
            ).to.be.reverted

            expect(await token.balanceOf(sender.address)
            ).to.be.eq(parseEther("0.0"))
        });
        it("should mint if called by a Minter", async () => {
            await expect(token.connect(deployer).mint(receiver.address, TWO_ETH)
            ).to.not.be.reverted

            expect(await token.balanceOf(receiver.address)
            ).to.be.eq(TWO_ETH)
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
