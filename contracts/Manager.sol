// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "./interfaces/IManager.sol";
import "./BondingCurve.sol";
import "./Token.sol";

/// @title Manager for Borealis contracts
/// @author Jamil B.
/**
 * @notice Manages the Bonding Curve and Token; is in charge of their evolution when
 * upgrades are needed.
*/
contract Manager is IManager, AccessControl {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    IToken public override token;
    IBondingCurve public override curve;

    constructor(address _weth){
        Token _token = new Token();
        address tokenAddress = address(_token);
        _setToken(tokenAddress);

        BondingCurve _curve = new BondingCurve(tokenAddress, _weth, address(this));
        _setCurve(address(_curve));

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
