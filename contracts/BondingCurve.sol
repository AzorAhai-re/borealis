// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./access/IAdmin.sol";
import "./interfaces/IBondingCurve.sol";
import "./interfaces/IMap.sol";
import "./Map.sol";

/// @title A title that should describe the contract/interface
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
contract BondingCurve is IBondingCurve, Map {
    // used to prevent delegate calls
    address private immutable originalContract;
    IManager internal manager;
    IWETH   private weth;
    IUniswapV3Pool public oracle;

    uint256 public constant targetSupply = 2501235447590;

    mapping(address => uint256) private promoBalance;
    mapping(address => UserAccount) private mintBalance;

    int128 internal XCD_USD;
    int128 internal growthDenNom;
    uint256 internal promoBonus;

    address public trustedUniUsdcEthPool;
    uint16 public promoEpoch;
    bool private initComplete;

    // ToDo: set on governance
    uint256 private rateLimitEpoch = 4 hours;
    // ToDo: set on governance
    uint256 private rateLimitThreshold = 5000 * 1e6;

    modifier noDelegateCall () {
        checkIfDelegateCall();
        _;
    }

    function checkIfDelegateCall() private view {
        require(address(this) == originalContract, "no delegate call");
    }

    constructor (
        address _token,
        address _weth,
        address _manager,
        address _oracle
    ) Map(_manager) {
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

        originalContract = address(this);
        weth = IWETH(_weth);
        manager = IManager(_manager);
        oracle = IUniswapV3Pool(_oracle);
    }

    function checkRateLimit(UserAccount storage _userAccount, uint256 collateral) private {
        require(collateral <= rateLimitThreshold, "rate limit: overspending collateral; can not purchase this much");

        if (!_userAccount.opened) {
            _userAccount.mintAllowance = rateLimitThreshold;
            _userAccount.opened = true;
        }

        if (_userAccount.mintAllowance < collateral) {
            if (
                (
                    block.timestamp - _userAccount.timeOfLastTrade >= rateLimitEpoch
                )
            ) {
                // refresh, or open account, mint allowance to be able to mint
                _userAccount.mintAllowance = rateLimitThreshold;
            }
            else {
                revert("rate limit: quantitative rate limit reached, please wait next RL epoch");
            }
        }
    }

    function usdEth() view internal returns (uint256) {
        (uint160 sqrtPricex96, , , , , ,) = oracle.slot0();

        uint256 u256SqrtPrice;
        require(
            (u256SqrtPrice = uint256(sqrtPricex96)) == sqrtPricex96,
            "Unsafe conversion from uint160 to uint256"
        );

        return u256SqrtPrice * u256SqrtPrice >> (192);
    }

    function finalUsdPrice(
        uint256 collateral,
        uint256 _usdEth,
        uint256 decimals
    ) internal pure returns (uint256) {
        return collateral * _usdEth / decimals;
    }

    function mintInitRewards() external override {
        require(!initComplete, "cannot call again");
        initComplete = true;
        IToken trustedToken = token();
        trustedToken.approve(address(trustedToken), 180573542300);
        trustedToken.mint(address(this), 180573542300);
    }

    function calcPricePerToken(uint256 supply) view public override returns (int128) {
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

    function bond(uint256 _wethInput) payable external override
        noDelegateCall
    {
        require(IAdmin(address(manager)).isBonder(msg.sender), "Bonding Curve: Not authorised to bond");
        require(!IAdmin(address(manager)).isPaused(), "Bonding Curve: bonding paused");
        require(
            (_wethInput > 0 && msg.value == 0) ||
            (msg.value > 0 && _wethInput == 0),
            "You can only bond with either WETH or ETH"
        );
        if (_wethInput > 0) {
            require(IERC20(address(weth)).allowance(msg.sender, address(this)) >= _wethInput, "Insufficient allowance for tx");
            require(IERC20(address(weth)).balanceOf(msg.sender) >= _wethInput, "You need > 0 WETH to bond");
        }
        IToken trustedToken = token();
        uint256 totalStart;
        uint256 totalEnd;
        UserAccount storage user = mintBalance[msg.sender];
        uint256 currSupply = trustedToken.totalSupply();

        uint256 usdEthPrice = usdEth();
        uint256 currSupplyUsd = ABDKMath64x64.toUInt(ABDKMath64x64.divu(currSupply * 10, 27));

        uint256 collateral = _wethInput == 0? msg.value : _wethInput;
        uint256 usdPrice = finalUsdPrice(collateral, usdEthPrice, 1e17);

        checkRateLimit(user, usdPrice);

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

        user.mintAllowance -= usdPrice;
        user.timeOfLastTrade = block.timestamp;
        user.balance += tokensToIssue;
        if (_wethInput > 0){
            (bool success, ) = address(weth).call(
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    msg.sender, address(this), collateral
                )
            );

            if (!success){
                user.balance -= tokensToIssue;
                revert("ERC20: WETH low level transfer failed");
            }
        } 
    }

    function approveBonding() external override {
        IAdmin(address(manager)).approveBonding(msg.sender);
    }

    function withdrawMintBalance() external override noDelegateCall {
        UserAccount storage user = mintBalance[msg.sender];

        require(user.opened, "user account is not opened");
        require(user.balance > 0, "you do not have any pending transfers");
        uint256 amount = user.balance;
        user.balance = 0;

        token().mint(msg.sender, amount);
    }

    function withdrawPromoBalance() external override noDelegateCall {
        require(promoBalance[msg.sender] > 0, "you do not have any pending transfers");
        uint256 amount = promoBalance[msg.sender];
        promoBalance[msg.sender] = 0;

        token().transfer(msg.sender, amount);
    }

    function setRateLimitThreshold(uint256 newThreshold) external override {
        require(IAdmin(address(manager)).isGovernor(msg.sender), "Bonding Curve: not authorized to set rate limit");
        rateLimitThreshold = newThreshold;
    }

}
