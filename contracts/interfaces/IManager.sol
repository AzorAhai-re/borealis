// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "./IToken.sol";
import "./IBondingCurve.sol";
import "../BondingCurve.sol";
import "../Token.sol";

/// @title Manager for Borealis contracts
/// @author Jamil B.
/**
 * @notice Manages the Bonding Curve and Token; is in charge of their evolution when
 * upgrades are needed.
*/
interface IManager {

    event CurveUpdated(address);
    event TokenUpdated(address);

    function curve() external view returns(IBondingCurve);
    function token() external view returns(IToken);

    function setCurve(address _curve) external;
    function setToken(address _token) external;
}
