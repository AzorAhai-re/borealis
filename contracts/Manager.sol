// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "./access/Admin.sol";
import "./interfaces/IManager.sol";
import "./BondingCurve.sol";
import "./Token.sol";

/// @title Manager for Borealis contracts
/// @author Jamil B.
/**
 * @notice Manages the Bonding Curve and Token; is in charge of their evolution when
 * upgrades are needed.
*/
contract Manager is IManager, Admin {

    IToken public override token;
    IBondingCurve public override curve;

    constructor(){
        Token _token = new Token(address(this));
        address tokenAddress = address(_token);
        _setToken(tokenAddress);

        _setupRole(GOVERNOR_ROLE, msg.sender);
    }

    function setToken(address _token) external override onlyRole(GOVERNOR_ROLE) {
        _setToken(_token);
    }

    function setCurve(address _curve) external override onlyRole(GOVERNOR_ROLE) {
        _setCurve(_curve);
    }

    function _setToken(address _token) internal {
        token = IToken(_token);

        emit TokenUpdated(_token);
    }

    function _setCurve(address _curve) internal {
        curve = IBondingCurve(_curve);

        emit CurveUpdated(_curve);
    }
}
