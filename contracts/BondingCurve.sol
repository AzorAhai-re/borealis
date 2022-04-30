// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "hardhat/console.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./Token.sol";
import "./NoDelegateCall.sol";
import "./libraries/ABDKMath64x64.sol";
import "./libraries/FullMath.sol";

/// @title A title that should describe the contract/interface
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
contract BondingCurve is Initializable, AccessControlUpgradeable, NoDelegateCall {
    Token _token;

    bytes32 public constant UNBOND_ROLE = keccak256("UNBOND");
    bytes32 public constant BOND_ROLE = keccak256("BOND");

    uint256 public constant targetSupply = 1355000000000;

    int128 internal XCD_USD;
    int128 internal GrowthDenNom;
    // int128 internal PromoBalance;
    // int128 internal Five;
    // int128 internal Thousand;

    address public uniUsdcEthPool;
    bool internal initComplete;
    bool public promoPeriod;

    event CollateralReceived(address, uint256);

    function init(
        address pool,
        address token) external initializer {
        _init_NDC();
        XCD_USD = ABDKMath64x64.fromUInt(27 * 1e5);
        GrowthDenNom = ABDKMath64x64.fromUInt(200000000000);
        // PromoBalance = ABDKMath64x64.fromUInt(180573542300);
        // Five = ABDKMath64x64.fromUInt(5);
        // Thousand = ABDKMath64x64.fromUInt(1000);

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

    function calcPricePerToken(uint256 supply) view public returns (int128) {
        int128 eExp = ABDKMath64x64.neg(
            ABDKMath64x64.div(
                ABDKMath64x64.fromUInt(supply),
                GrowthDenNom
            )
        );
        int128 exponentiated_component = ABDKMath64x64.exp(eExp);

        return (ABDKMath64x64.mul(XCD_USD, ABDKMath64x64.sub(ABDKMath64x64.fromUInt(1), exponentiated_component)));
    }

    function calcLogIntegral(uint256 supply) view internal returns (uint256) {
        int256 eExp = - (int256(supply * 1e5) / 2e11);

        int128 exponentiated_component = ABDKMath64x64.inv(ABDKMath64x64.pow(ABDKMath64x64.fromUInt(2), uint256(ABDKMath64x64.muli(ABDKMath64x64.log_2(ABDKMath64x64.exp(1)), - int256(eExp)))));
        int128 multipliedBy = ABDKMath64x64.add(ABDKMath64x64.fromUInt(supply), ABDKMath64x64.mul(GrowthDenNom, exponentiated_component));

        return(ABDKMath64x64.mulu(multipliedBy, 27 * 1e5));
    }

    function bond() payable external
        noDelegateCall
        onlyRole(BOND_ROLE)
    {
        uint256 totalStart;
        uint256 totalEnd;
        uint256 currSupply = _token.totalSupply();

        uint256 usdEthPrice = usdEth();
        uint256 currSupplyUsd = ABDKMath64x64.toUInt(ABDKMath64x64.divu(currSupply * 1e2, 271));

        uint256 usdPrice = msg.value / usdEthPrice;
        uint256 xcdDemand = FullMath.mulDivRoundingUp(usdPrice, 27, 10);

        // uint256 tokenSpotPrice = ABDKMath64x64.toUInt(calcPricePerToken(currSupply + 1e6));

        // console.log("\t- price per token before bonding: ", tokenSpotPrice);

        totalStart = calcLogIntegral(currSupplyUsd);
        totalEnd = calcLogIntegral(currSupplyUsd + xcdDemand);

        uint256 tokensToIssue = (totalEnd - totalStart) / 1e4;

        // The following predicate checks whether or not the
        // promotional period has ended
        // if (promoPeriod) {
        //     int128 currPrice = calcPricePerToken(currSupply + tokensToIssue);
        //     int128 inflationScale = ABDKMath64x64.div(ABDKMath64x64.sub(XCD_USD, currPrice), XCD_USD);
        //     uint256 amountOwed = ABDKMath64x64.toUInt(ABDKMath64x64.div(ABDKMath64x64.mul(ABDKMath64x64.mul(inflationScale, PromoBalance), Five), Thousand));
        //     console.log("promo amount owed: ", amountOwed);

        //     _token.transfer(msg.sender, amountOwed);
        // }

        _token.mint(msg.sender, tokensToIssue);
    }

    function approveBonding() noDelegateCall external {
        require(!hasRole(BOND_ROLE, msg.sender), "`msg.sender` already has the BOND role");

        _setupRole(BOND_ROLE, msg.sender);
    }

    receive() external payable {
        emit CollateralReceived(msg.sender, msg.value);
    }
}
