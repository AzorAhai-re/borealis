import { ethers, upgrades } from "hardhat"

import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { BigNumber, BigNumberish, Wallet, constants } from "ethers"
import {
    keccak256, solidityPack, defaultAbiCoder,
    isAddress, isBytesLike
} from "ethers/lib/utils"

import { Token, BondingCurve } from "../../typechain-types"

const UniPoolArtifact = require("@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json");
// const UniPoolFactArtifact = require("@uniswap/v2-core/build/UniswapV2Factory.json");

export const deployContracts  = async (deployer?: SignerWithAddress) => {
    deployer = deployer ? deployer : (await ethers.getSigners())[0];

    const fakeWETH9Factory = await ethers.getContractFactory("ERC20");
    const fakeWETH9 = await fakeWETH9Factory.deploy("Wrapped Ether", "WETH");
    await fakeWETH9.deployed();

    const managerFactory = await ethers.getContractFactory("Manager");
    const manager = await managerFactory.deploy();
    await manager.deployed();

    const fakeUniUsdcWethPoolFactory = await ethers.getContractFactory("UniswapV3Pool", deployer);
    const fakeUniUsdcWethPool = await fakeUniUsdcWethPoolFactory.deploy();
    await fakeUniUsdcWethPool.deployed();

    const curveFactory = await ethers.getContractFactory("BondingCurve");
    const curve = await curveFactory.deploy(
        await manager.token(),
        fakeWETH9.address,
        manager.address,
        fakeUniUsdcWethPool.address
    );
    await curve.deployed();
    await manager.connect(deployer).setCurve(curve.address);

    const tokenFactory = await ethers.getContractFactory("Token");
    const token = new ethers.Contract(await manager.token(), tokenFactory.interface, deployer);
    await token.deployed();
    await manager.approveMint(deployer.address);
    await manager.approveBurn(deployer.address);

    await manager.approveMint(curve.address);
    await curve.mintInitRewards();

    return {"manager": manager, "curve": curve as BondingCurve, "token": token as Token}
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
