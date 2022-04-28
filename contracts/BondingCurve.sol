// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "hardhat/console.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./Token.sol";
import "./libraries/ABDKMathQuad.sol";
import "./libraries/FullMath.sol";

/// @title A title that should describe the contract/interface
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
contract BondingCurve is Initializable, AccessControlUpgradeable {
    Token _token;

    bytes32 public constant UNBOND_ROLE = keccak256("UNBOND");
    bytes32 public constant BOND_ROLE = keccak256("BOND");

    uint256 public constant targetSupply = 1355000000000;

    bytes16 internal XCD_USD;
    bytes16 internal GrowthDenNom;
    // bytes16 internal PromoBalance;
    // bytes16 internal Five;
    // bytes16 internal Thousand;

    address public uniUsdcEthPool;
    bool internal initComplete;
    bool public promoPeriod;

    event CollateralReceived(address, uint256);

    function init(
        address pool,
        address token) external initializer {
        XCD_USD = ABDKMathQuad.fromUInt(27 * 1e5);
        GrowthDenNom = ABDKMathQuad.fromUInt(200000000000);
        // PromoBalance = ABDKMathQuad.fromUInt(180573542300);
        // Five = ABDKMathQuad.fromUInt(5);
        // Thousand = ABDKMathQuad.fromUInt(1000);

        _token = Token(token);
        uniUsdcEthPool = pool;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function usdEth() view internal returns (uint256) {
        (uint160 sqrtPricex96, , , , , ,) = IUniswapV3Pool(uniUsdcEthPool).slot0();

        uint256 u256SqrtPrice;
        require(
            (u256SqrtPrice = uint256(sqrtPricex96)) == sqrtPricex96,
            "Unsafe conversion from uint160 to uint256"
        );

        return u256SqrtPrice * u256SqrtPrice >> (192);
    }

    function mintInitRewards() external {
        require(!initComplete, "cannot call again");
        _token.approve(address(_token), 180573542300);
        _token.mint(address(this), 180573542300);
        promoPeriod = true;

        initComplete = true;
    }

    function calcPricePerToken(uint256 supply) view internal returns (bytes16) {
        bytes16 eExp = ABDKMathQuad.neg(
            ABDKMathQuad.div(
                ABDKMathQuad.fromUInt(supply),
                GrowthDenNom
            )
        );
        bytes16 exponentiated_component = ABDKMathQuad.exp(eExp);

        
        return (ABDKMathQuad.mul(XCD_USD, ABDKMathQuad.sub(ABDKMathQuad.fromUInt(1), exponentiated_component)));
    }

    function calcLogIntegral(uint256 supply) view internal returns (bytes16) {
        bytes16 eExp = ABDKMathQuad.neg(
            ABDKMathQuad.div(
                ABDKMathQuad.fromUInt(supply),
                GrowthDenNom
            )
        );

        bytes16 exponentiated_component = ABDKMathQuad.exp(eExp);
        return(ABDKMathQuad.mul(XCD_USD, ABDKMathQuad.add(ABDKMathQuad.fromUInt(supply), ABDKMathQuad.mul(GrowthDenNom, exponentiated_component))));
    }

    function bond() payable external onlyRole(BOND_ROLE) {
        uint256 totalStart;
        uint256 totalEnd;
        uint256 currSupply = _token.totalSupply();

        uint256 usdEthPrice = usdEth();
        uint256 currSupplyUsd = currSupply / (27 * 1e5);
        console.log("\t- current supply", currSupplyUsd);
        console.log("\t- usd_eth spot price", usdEthPrice);
        uint256 usdPrice = msg.value / usdEthPrice;
        uint xcdDemand = FullMath.mulDivRoundingUp(usdPrice, 271, 100);

        // uint256 tokenSpotPrice = ABDKMathQuad.toUInt(calcPricePerToken(currSupply + 1e6));
        console.log("\t- usd price of msg.value: ", usdPrice / 1e4);
        console.log("\t- xcd price of msg.value: ", xcdDemand / 1e4);

        // console.log("\t- price per token before bonding: ", tokenSpotPrice);

        totalStart += ABDKMathQuad.toUInt(calcLogIntegral(currSupplyUsd));
        totalEnd += ABDKMathQuad.toUInt(calcLogIntegral(currSupplyUsd + xcdDemand));

        uint256 tokensToIssue = (totalEnd - totalStart) / 1e4;

        console.log("\t- total tokens owed: ", tokensToIssue);

        // The following predicate checks whether or not the
        // promotional period has ended
        // if (promoPeriod) {
        //     bytes16 currPrice = calcPricePerToken(currSupply + tokensToIssue);
        //     bytes16 inflationScale = ABDKMathQuad.div(ABDKMathQuad.sub(XCD_USD, currPrice), XCD_USD);
        //     uint256 amountOwed = ABDKMathQuad.toUInt(ABDKMathQuad.div(ABDKMathQuad.mul(ABDKMathQuad.mul(inflationScale, PromoBalance), Five), Thousand));
        //     console.log("promo amount owed: ", amountOwed);

        //     _token.transfer(msg.sender, amountOwed);
        // }

        _token.mint(msg.sender, tokensToIssue);
    }

    receive() external payable {
        emit CollateralReceived(msg.sender, msg.value);
    }
}
