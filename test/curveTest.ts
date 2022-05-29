import chai, {expect, should} from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { ethers, GetGas } from "hardhat";

import { ABDKMath64x64Mock, BondingCurve, Token, UniswapV3Pool } from "../typechain-types";
import { deployToken, deployCurve } from "./utils/helpers";

describe("Bonding Curve Test", function () {

    let token: Token;
    let curve: BondingCurve;
    let math: ABDKMath64x64Mock;
    let pool: UniswapV3Pool;

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

        const PoolFactory = await ethers.getContractFactory("UniswapV3Pool");
        pool = await PoolFactory.deploy();

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
        ).to.be.lt(10);

        return tokenSpotPrice
    }

    describe("Bonding", async () => {
        it("should cosmetically prove to be an increasing function up till the h-asymptote",async () => {
            await curve.connect(bonder).approveBonding();
            const stage0 = await getSpotPrice();

            await curve.connect(bonder).bond(0, {value: parseEther("1")});
            await curve.connect(bonder).withdrawMintBalance();
            await curve.connect(bonder).withdrawPromoBalance();
            const stage1 = await getSpotPrice();

            await curve.connect(bonder).bond(0, {value: parseEther("10")});
            await curve.connect(bonder).withdrawMintBalance();
            await curve.connect(bonder).withdrawPromoBalance();
            const stage2 = await getSpotPrice();

            // at this point, the price has stabilised
            await curve.connect(bonder).bond(0, {value: parseEther("100")});
            await curve.connect(bonder).withdrawMintBalance();
            await curve.connect(bonder).withdrawPromoBalance();
            const stage3 = await getSpotPrice();

            expect(stage1).to.be.gt(stage0,
                `Stage 1 should be greater than ${stage0}`
            )
            expect(stage2).to.be.gt(stage1,
                `Stage 2 should be greater than ${stage1}`
            )
            expect(stage3).to.be.gte(stage2,
                `Stage 3 should be greater than or equal to ${stage2}`
            )
        });

        it("should be able to bond 0.3 ETH worth of {token_symbol}", async () => {
            const tx_gas_approve = await GetGas(await curve.connect(bonder).approveBonding());
            const current_supply = (await token.totalSupply()).div(xcdUsd);
            const tx_gas_bond = await GetGas(await curve.connect(bonder).bond(0, {value: parseEther("0.3")}));
            await curve.connect(bonder).withdrawMintBalance();
            await curve.connect(bonder).withdrawPromoBalance();

            const slot0 = await pool.slot0();
            const sqrtPriceX96 = slot0.sqrtPriceX96; 
            const usdEthPrice = sqrtPriceX96.pow(2).div(BigNumber.from(2).pow(192));
            const usdMsgValue = parseEther("0.3").div(usdEthPrice);
            const xcdDemand = usdMsgValue.toNumber() * 2.7;

            const tokenWeight0 = 2.7 * ((current_supply.toNumber() / 1e6) + Math.E ** (0 - (current_supply.toNumber() / 1e6) / 200000));
            const tokenWeight1 = 2.7 * (((current_supply.toNumber() + xcdDemand) / 1e6) + Math.E ** (0 - (current_supply.toNumber() / 1e6) / 200000));

            let expTokensOwed = tokenWeight1 - tokenWeight0
            expTokensOwed += 180573.5423 * 5e-5; // add the promo bonus
            // console.log("expTokensOwed: ", expTokensOwed)
            // Check that the precision of the amount of tokens owed to the bonder
            // is sufficiently high; less than 1e-5 difference from off-chain calculation
            expect(
                Math.abs((await token.balanceOf(bonder.address)).toNumber() - Math.floor(expTokensOwed * 1e6))
            ).to.be.lt(10,
                `expecting the bonder's token balance to be ~= to ${expTokensOwed}`
            );

            expect(await ethers.provider.getBalance(curve.address)).to.be.eq(parseEther("0.3"));
            console.log(`        ⛽ approveBonding (${tx_gas_approve} gas)`);
            console.log(`        ⛽ bond (${tx_gas_bond} gas)`);
        });

        it("should stabalise the price once the threshold has been reached", async () => {
            // mint to the threashold amount
            // with the bond-deploy-mint already in the currSupply, this takes
            // the curve way past the beginning of the "threshhold domain"
            await token.connect(deployer).mint(receiver.address, 2962491838571 - 180573542300);
            await curve.connect(bonder).approveBonding();
            
            await checkSpotPrice();
            await curve.connect(bonder).bond(0, {value: parseEther("1000")});
            await checkSpotPrice();
            await curve.connect(bonder).bond(0, {value: parseEther("1000")});
            await checkSpotPrice();
        });
    });

    
})
