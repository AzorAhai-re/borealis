import chai, {expect, should} from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Contract } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";

import { BondingCurve, Token } from "../typechain-types";
import { deployToken, deployCurve } from "./utils/helpers";

describe("Bonding Curve Test", function () {

    let token: Token;
    let curve: BondingCurve;

    let deployer: SignerWithAddress;
    let bonder: SignerWithAddress;
    let receiver: SignerWithAddress;
    let nonAdmin: SignerWithAddress;
    
    beforeEach(async () => {
        [ deployer, bonder, receiver, nonAdmin ] = await ethers.getSigners()

        token = await deployToken(deployer)
        const { bondingCurve } = await deployCurve(deployer, token)
        curve = bondingCurve
    });

    describe("Bonding", async () => {
        it("should be able to bond 1 token", async () => {
            await curve.grantRole(await curve.BOND_ROLE(), bonder.address);
            const xcdUsd = BigNumber.from(27 * 1e5);
            const current_supply = (await token.totalSupply()).div(xcdUsd);
            await curve.connect(bonder).bond({value: parseEther("0.3")});

            const tokenWeight0 = 2.7 * ((current_supply.toNumber() / 1e6) + Math.E ** (0 - (current_supply.toNumber() / 1e6) / 200000));
            const tokenWeight1 = 2.7 * (((current_supply.toNumber() / 1e6) + 2351.15) + Math.E ** (0 - (current_supply.toNumber() / 1e6) / 200000));

            const expTokensOwed = tokenWeight1 - tokenWeight0

            expect(
                Math.abs((await token.balanceOf(bonder.address)).toNumber() - Math.floor(expTokensOwed * 1e8))
            ).to.be.lt(1e6,
                `expecting the bonder's token balance to be ~= to ${expTokensOwed}`
            );
        });
    });

    
})