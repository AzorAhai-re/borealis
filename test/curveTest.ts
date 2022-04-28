import chai, {expect, should} from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";

import { Token, BondingCurve } from "../typechain-types";
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
            await curve.connect(bonder).bond({value: parseEther("0.3")});

            // check for balance to be equal to ts computed price instead
            // of hardcoded price
            expect(await token.balanceOf(bonder.address)).to.be.eq(BigNumber.from("3716963887"));
        });
    });

    
})
