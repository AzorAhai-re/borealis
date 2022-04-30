import chai, {expect, should} from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Contract } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";

import { BondingCurve, Token, ABDKMath64x64Mock } from "../typechain-types";
import { deployToken, deployCurve } from "./utils/helpers";

describe("Bonding Curve Test", function () {

    let token: Token;
    let curve: BondingCurve;
    let math: ABDKMath64x64Mock;

    let deployer: SignerWithAddress;
    let bonder: SignerWithAddress;
    let receiver: SignerWithAddress;
    let nonAdmin: SignerWithAddress;

    let xcdUsd: BigNumber;
    
    beforeEach(async () => {
        [ deployer, bonder, receiver, nonAdmin ] = await ethers.getSigners()

        token = await deployToken(deployer)
        const { bondingCurve } = await deployCurve(deployer, token)
        curve = bondingCurve

        const MathFactory = await ethers.getContractFactory("ABDKMath64x64Mock");
        math = await MathFactory.deploy();

        xcdUsd = BigNumber.from(27 * 1e5);
    });

    async function getSpotPrice(){
        const current_supply = await token.totalSupply();
        const tokenSpotPrice = await math.toUInt(await curve.calcPricePerToken(current_supply.add(1e6)))

        return tokenSpotPrice
    }

    async function checkSpotPrice(){
        const current_supply = await token.totalSupply();
        const tokenSpotPrice = await math.toUInt(await curve.calcPricePerToken(current_supply.add(1e6)))
        expect(Math.abs(tokenSpotPrice.sub(2700000).toNumber())
        ).to.be.lt(1e5);

        return tokenSpotPrice
    }

    describe("Bonding", async () => {
        it("should cosmetically prove to be an increasing function up till the h-asymptote",async () => {
            await curve.connect(bonder).approveBonding();
            const stage0 = await getSpotPrice();

            await curve.connect(bonder).bond({value: parseEther("1")});
            const stage1 = await getSpotPrice();

            await curve.connect(bonder).bond({value: parseEther("10")});
            const stage2 = await getSpotPrice();

            // at this point, the price has stabilised
            await curve.connect(bonder).bond({value: parseEther("100")});
            const stage3 = await getSpotPrice();

            expect(stage1).to.be.gt(stage0,
                `Stage 1 should be greater than ${stage0}`
            )
            expect(stage2).to.be.gt(stage1,
                `Stage 2 should be greater than ${stage1}`
            )
            expect(stage3).to.be.eq(stage2,
                `Stage 3 should be greater than or equal to ${stage2}`
            )
        });

        it("should be able to bond 0.3 ETH worth of {token_symbol}", async () => {
            await curve.connect(bonder).approveBonding();
            const current_supply = (await token.totalSupply()).div(xcdUsd);
            const tx_queue = await curve.connect(bonder).bond({value: parseEther("0.3")});
            // const tx_receipt = tx_queue.wait();

            const tokenWeight0 = 2.7 * ((current_supply.toNumber() / 1e6) + Math.E ** (0 - (current_supply.toNumber() / 1e6) / 200000));
            const tokenWeight1 = 2.7 * (((current_supply.toNumber() / 1e6) + 2351.15) + Math.E ** (0 - (current_supply.toNumber() / 1e6) / 200000));

            const expTokensOwed = tokenWeight1 - tokenWeight0

            expect(
                Math.abs((await token.balanceOf(bonder.address)).toNumber() - Math.floor(expTokensOwed * 1e8))
            ).to.be.lt(1e6,
                `expecting the bonder's token balance to be ~= to ${expTokensOwed}`
            );

            expect(await ethers.provider.getBalance(curve.address)).to.be.eq(parseEther("0.3"));
        });

        it("should stabalise the price once the threshold has been reached", async () => {
            // mint to the threashold amount
            // with the bond-deploy-mint already in the currSupply, this takes
            // the curve way past the beginning of the "threshhold domain"
            await token.connect(deployer).mint(receiver.address, 2962491838571 - 180573542300);
            await curve.connect(bonder).approveBonding();
            
            await checkSpotPrice();
            await curve.connect(bonder).bond({value: parseEther("1000")});
            await checkSpotPrice();
            await curve.connect(bonder).bond({value: parseEther("1000")});
            await checkSpotPrice();
        });
    });

    
})
