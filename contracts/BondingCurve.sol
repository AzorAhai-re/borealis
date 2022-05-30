// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "hardhat/console.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "./interfaces/IToken.sol";
import "./libraries/ABDKMath64x64.sol";
import "./libraries/FullMath.sol";

/// @title A title that should describe the contract/interface
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
contract BondingCurve is AccessControl, Pausable {
    // used to prevent delegate calls
    address private immutable originalContract;
    address private uniV2Pool;
    address private wethPool;
    address private weth;
    IToken internal trustedToken;

    bytes32 public constant UNBOND_ROLE = keccak256("UNBOND");
    bytes32 public constant BOND_ROLE = keccak256("BOND");
    uint256 public constant targetSupply = 2501235447590;

    mapping(address => uint256) private promoBalance;
    mapping(address => uint256) private mintBalance;

    int128 internal XCD_USD;
    int128 internal growthDenNom;
    uint256 internal promoBonus;

    address public trustedUniUsdcEthPool;
    bool internal initComplete;
    uint16 promoEpoch;

    event CollateralReceived(address, uint256);

    modifier noDelegateCall () {
        checkIfDelegateCall();
        _;
    }

    function checkIfDelegateCall() private view {
        require(address(this) == originalContract, "no delegate call");
    }

    function pauseBonding() public onlyRole(DEFAULT_ADMIN_ROLE){
        _pause();
    }

    constructor (address _uniUsdcEthPool, address _uniV2Fact, address _token, address _weth, address _wethPool) {
        require(IERC20Metadata(_weth).decimals() == 18, "can't account for collateral of token if decimals != 18");
        require(IERC20Metadata(_token).decimals() == 6, "can't account for crypto-fiat token if decimals != 6");

        XCD_USD = ABDKMath64x64.fromUInt(27 * 1e5);
        growthDenNom = ABDKMath64x64.fromUInt(200000000000);

        promoBonus =
                ABDKMath64x64.toUInt(
                    ABDKMath64x64.div(
                        ABDKMath64x64.mul(
                            ABDKMath64x64.fromUInt(180573542300),
                            ABDKMath64x64.fromUInt(5)
                        ),
                        ABDKMath64x64.fromUInt(100000)
                    )
                );

        trustedUniUsdcEthPool = _uniUsdcEthPool;
        originalContract = address(this);

        uniV2Pool = IUniswapV2Factory(_uniV2Fact).createPair(_token, _weth);
        weth = _weth;
        wethPool = _wethPool;

        trustedToken = IToken(_token);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function usdEth() view internal returns (uint256) {
        (uint160 sqrtPricex96, , , , , ,) = IUniswapV3Pool(trustedUniUsdcEthPool).slot0();

        uint256 u256SqrtPrice;
        require(
            (u256SqrtPrice = uint256(sqrtPricex96)) == sqrtPricex96,
            "Unsafe conversion from uint160 to uint256"
        );

        return u256SqrtPrice * u256SqrtPrice >> (192);
    }

    function mintInitRewards() external {
        trustedToken.approve(address(trustedToken), 180573542300);
        trustedToken.mint(address(this), 180573542300);
        require(!initComplete, "cannot call again");
        initComplete = true;
    }

    function calcPricePerToken(uint256 supply) view public returns (int128) {
        int128 eExp = ABDKMath64x64.neg(
            ABDKMath64x64.div(
                ABDKMath64x64.fromUInt(supply),
                growthDenNom
            )
        );
        int128 exponentiated_component = ABDKMath64x64.exp(eExp);

        return (ABDKMath64x64.mul(XCD_USD, ABDKMath64x64.sub(ABDKMath64x64.fromUInt(1), exponentiated_component)));
    }

    function calcLogIntegral(uint256 supply) view internal returns (uint256) {
        int256 eExp = - (int256(supply * 1e5) / 2e11);

        int128 exponentiated_component = ABDKMath64x64.inv(ABDKMath64x64.pow(ABDKMath64x64.fromUInt(2), uint256(ABDKMath64x64.muli(ABDKMath64x64.log_2(ABDKMath64x64.exp(1)), - int256(eExp)))));
        int128 multipliedBy = ABDKMath64x64.add(ABDKMath64x64.fromUInt(supply), ABDKMath64x64.mul(growthDenNom, exponentiated_component));

        return(ABDKMath64x64.mulu(multipliedBy, 27 * 1e5));
    }

    function bond(uint256 _wethInput) payable external
        onlyRole(BOND_ROLE)
        noDelegateCall
        whenNotPaused
    {
        require(
            (_wethInput > 0 && msg.value == 0) ||
            (msg.value > 0 && _wethInput == 0),
            "You can only bond with either WETH or ETH"
        );
        if (_wethInput > 0) {
            require(IERC20(weth).allowance(msg.sender, address(this)) >= _wethInput, "Insufficient allowance for tx");
            require(IERC20(weth).balanceOf(msg.sender) >= _wethInput, "You need > 0 WETH to bond");
        }
        uint256 totalStart;
        uint256 totalEnd;
        uint256 currSupply = trustedToken.totalSupply();

        uint256 usdEthPrice = usdEth();
        uint256 currSupplyUsd = ABDKMath64x64.toUInt(ABDKMath64x64.divu(currSupply * 10, 27));

        uint256 collateral = _wethInput == 0? msg.value : _wethInput;
        uint256 usdPrice = collateral / usdEthPrice;
        uint256 xcdDemand = usdPrice * 27 / 10;

        totalStart = calcLogIntegral(currSupplyUsd);
        totalEnd = calcLogIntegral(currSupplyUsd + xcdDemand);

        uint256 tokensToIssue = (totalEnd - totalStart) / 1e6;

        // The following predicate checks whether or not the
        // promotional period has ended and gives the user a mint
        // bonus if they haven't already

        if (promoEpoch < 200000 && promoBalance[msg.sender] == 0) {
            promoEpoch += 1;
            uint256 curveBalance = trustedToken.balanceOf(address(this));
            if (promoBonus > curveBalance){
                promoBalance[msg.sender] += curveBalance;
            } else {
                promoBalance[msg.sender] += promoBonus;
            }
        }

        mintBalance[msg.sender] += tokensToIssue;
        if (_wethInput > 0){
            (bool success, ) = weth.call(
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    msg.sender, address(this), collateral
                )
            );

            if (!success){
                mintBalance[msg.sender] -= tokensToIssue;
                revert("ERC20: WETH low level transfer failed");
            }
        } 
    }

    function withdrawMintBalance() noDelegateCall external {
        require(mintBalance[msg.sender] > 0, "you do not have any pending transfers");
        trustedToken.mint(msg.sender, mintBalance[msg.sender]);
    }

    function withdrawPromoBalance() noDelegateCall external {
        require(promoBalance[msg.sender] > 0, "you do not have any pending transfers");
        trustedToken.transfer(msg.sender, promoBalance[msg.sender]);
    }

    function approveBonding() external whenNotPaused {
        require(msg.sender != address(0), "hey, no funny business!");
        require(!hasRole(BOND_ROLE, msg.sender), "`msg.sender` already has the BOND role");

        _setupRole(BOND_ROLE, msg.sender);
    }

}
