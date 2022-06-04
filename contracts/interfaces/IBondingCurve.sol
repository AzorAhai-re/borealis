// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

import "./IToken.sol";
import "../libraries/ABDKMath64x64.sol";
import "../libraries/FullMath.sol";

/// @title A title that should describe the contract/interface
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
interface IBondingCurve {

    struct UserAccount{
        bool opened;
        uint256 balance;
        uint256 timeOfLastTrade;
        uint256 mintAllowance;
    }

    event CollateralReceived(address, uint256);

    function calcPricePerToken(uint256 supply) view external returns (int128);

    function mintInitRewards() external;

    function bond(uint256 _wethInput) payable external;

    function withdrawMintBalance() external;

    function withdrawPromoBalance() external;

    function setRateLimitThreshold(uint256 newThreshold) external;

}
