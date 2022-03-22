import { ethers, upgrades } from "hardhat"

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { BigNumber, BigNumberish, Wallet } from "ethers"
import {
    keccak256, solidityPack, defaultAbiCoder,
    isAddress, isBytesLike
} from "ethers/lib/utils"

import { Token } from "../../typechain-types"

export const deployToken = async (deployer?: SignerWithAddress) => {
    deployer = deployer ? deployer : (await ethers.getSigners())[0]

    const tokenFactory = await ethers.getContractFactory("Token", deployer)
    const version = 1

    const token = await upgrades.deployProxy(tokenFactory, [deployer.address, 1], { initializer: "init" }) as Token
    await token.deployed()

    await token.grantRole(await token.MINTER_ROLE(), deployer.address)
    await token.grantRole(await token.BURNER_ROLE(), deployer.address)

    return token
}

export const getPermitDigest = async (
    token: Token, payload: 
        { owner: string, spender: string, amount: BigNumber },
    nonce: BigNumber, deadline: BigNumber) => {
        const DOMAIN_SEPARATOR = token.DOMAIN_SEPARATOR()
        const PERMIT_HASH = token.PERMIT_TYPEHASH()

        const digest = keccak256(
            solidityPack(
                ["bytes1", "bytes1", "bytes32", "bytes32"],
                [
                    '0x19', '0x01',
                    await DOMAIN_SEPARATOR,
                    keccak256(
                        defaultAbiCoder.encode(
                            [
                                'bytes32', 'address', 'address',
                                'uint256', 'uint256', 'uint256'],
                            [
                                await PERMIT_HASH, payload.owner, payload.spender,
                                payload.amount, nonce, deadline]
                        )
                    )
                ]
            )
        );

        return digest
    }

export const get_raw_signature  = async (
    permit: string,
    signer: SignerWithAddress | Wallet,
    contract: string,
    spender: string,
    amount: BigNumberish,
    nonce: BigNumberish,
    deadline: BigNumberish
) => {
    const domain = {
        name: "{token_name}",
        version: '1',
        chainId: 31337,
        verifyingContract: contract
    }

    const types = {
        Permit : [
            {name: "permitHash", type: "bytes32"},
            {name: "owner", type: "address"},
            {name: "spender", type: "address"},
            {name: "value", type: "uint256"},
            {name: "nonce", type: "uint256"},
            {name: "deadline", type: "uint256"},
        ]
    }

    const value = {
        permitHash: isBytesLike(permit) ? permit : null,
        owner: isAddress(signer.address) ? signer.address : null,
        spender: isAddress(spender) ? spender : null,
        value: amount,
        nonce: nonce,
        deadline: deadline,
    }

    return signer._signTypedData(domain, types, value)
}
