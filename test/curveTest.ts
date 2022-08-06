import chai, {expect, should} from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { ethers, GetGas } from "hardhat";

import { ABDKMath64x64Mock, BondingCurve, Token, Manager, UniswapV3Pool } from "../typechain-types";
import { deployContracts, consultPriceAtTick } from "./utils/helpers";

describe("Bonding Curve Test", function () {

    let token: Token;
    let curve: BondingCurve;
    let manager: Manager;
    let math: ABDKMath64x64Mock;
    let pool: UniswapV3Pool;

    let deployer: SignerWithAddress;
    let bonder: SignerWithAddress;
    let receiver: SignerWithAddress;
    let nonAdmin: SignerWithAddress;
    let notAuthorized: SignerWithAddress;

    let xcdUsd: BigNumber;
    
    beforeEach(async () => {
        [ deployer, bonder, receiver, nonAdmin, notAuthorized ] = await ethers.getSigners();

        const contracts = await deployContracts(deployer);
        curve = contracts.curve;
        token = contracts.token;
        manager = contracts.manager;

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
        const tokenSpotPrice = await getSpotPrice()
        expect(Math.abs(tokenSpotPrice.sub(2700000).toNumber())
        ).to.be.lt(10);

        return tokenSpotPrice
    }

    describe("Bond", async () => {
        it("should not initialize minting rewards twice", async () => {
            await expect(
                curve.connect(deployer).mintInitRewards()
            ).to.be.revertedWith("cannot call again");
        });
        it("should not allow bonding unless approved", async () => {
            await expect(
                curve.connect(notAuthorized).bond(0, {value: parseEther("0.03")})
            ).to.be.revertedWith("Bonding Curve: Not authorised to bond");
        });
        it("should not be able to withdraw/mint Token if account unopened", async () => {
            await expect(
                curve.connect(receiver).withdrawMintBalance()
            ).to.be.revertedWith("user account is not opened");
        });

        it("should cosmetically prove to be an increasing function up till the h-asymptote", async () => {
            // await curve.connect(bonder).approveBonding();
            await curve.connect(bonder).approveBonding();
            await curve.connect(deployer).setRateLimitThreshold(parseEther("5000"));
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

            const usdEthPrice = await consultPriceAtTick(pool)

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
            await curve.connect(deployer).setRateLimitThreshold(parseEther("5000"));
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

    describe("Rate Limit", async () => {
        let limitInEth: number;

        async function changeLimitInEth(newLimit: number) {
            const usdEthPrice = await consultPriceAtTick(pool)

            limitInEth = newLimit * (usdEthPrice.toNumber() / 1e12)
        }

        beforeEach(async () => {
            await changeLimitInEth(5000)
        });

        it("should only allow the governor to set a rate limit", async () => {
            await expect(
                curve.connect(deployer).setRateLimitThreshold(1500 * 1e6)
            ).to.not.be.reverted

            await expect(
                curve.connect(bonder).setRateLimitThreshold(6000 * 1e6)
            ).to.be.revertedWith("Bonding Curve: not authorized to set rate limit")
        });

        it("should not allow bonding above collateral rate limit", async () => {
            await curve.connect(bonder).approveBonding();
            await expect(
                // precision on contract is 6 decimal places
                // so we nudge the limit by 1e-7 to ensure we're just over the limit
                curve.connect(bonder).bond(0, {value: parseEther((limitInEth + 1e-7).toString())})
            ).to.be.revertedWith("rate limit: overspending collateral; can not purchase this much")

        });

        it("should be able to change rate limit if governor", async () => {
            await curve.connect(deployer).setRateLimitThreshold(1500 * 1e6)

            await curve.connect(bonder).approveBonding();
            await changeLimitInEth(1500)
            await expect(
                curve.connect(bonder).bond(0, {value: parseEther(limitInEth.toString())})
            ).to.not.be.reverted

            await expect(
                curve.connect(bonder).bond(0, {value: parseEther((limitInEth + 1e-7).toString())})
            ).to.be.revertedWith("rate limit: overspending collateral; can not purchase this much")
        });
    });

    describe("Withdraw", async () => {
        beforeEach(async () => {
            await curve.connect(bonder).approveBonding();
            await curve.connect(bonder).bond(0, {value: parseEther("0.3")});
        });

        it("should not be able to withdraw/mint Token if account does not have a balance", async () => {
            await curve.connect(bonder).withdrawMintBalance();
            await expect(
                curve.connect(bonder).withdrawMintBalance()
            ).to.be.revertedWith("you do not have any pending transfers");
        });
        it("should not be able to withdraw promo Token if account does not have any pending", async () => {
            await curve.connect(bonder).withdrawPromoBalance();
            await expect(
                curve.connect(bonder).withdrawPromoBalance()
            ).to.be.revertedWith("you do not have any pending transfers")
        });
    });
})
