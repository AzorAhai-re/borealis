// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.4;

import "./Token.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @title A title that should describe the contract/interface
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
contract BondingCurve is Initializable, AccessControlUpgradeable {
    Token _token;

    bytes32 public constant UNBOND_ROLE = keccak256("UNBOND");
    bytes32 public constant BOND_ROLE = keccak256("BOND");

    uint256 public constant targetSupply = 1355000000000000000000000;

    uint256 public constant eNume = 2718281828459045235;
    uint256 public constant eDeNom = 1000000000000000000;

    uint256 public constant startValueNume = 14760147601476015;
    uint256 public constant startValueDeNom = 1000000000000000000000000;

    uint256 public constant growthDenNom = 200000000000000000000000;

    uint256 public promoEpoch;

    event CollateralReceived(address, uint256);

    function init(address token) external initializer {
        _token = Token(token);
        mintInitRewards();
    }

    function mintInitRewards() internal onlyInitializing {
        _token.approve(address(_token), 180573542300000000000000);
        _token.mint(address(this), 180573542300000000000000);
    }

    function calcLogIntegral(uint256 supply) pure internal returns (uint256) {
        return (
            (37 * (
                supply + growthDenNom * (
                    (eNume ** (0 - supply / growthDenNom)
                    ) / eDeNom))
            )/ 100
        );
    }

    function bond(uint256 num) payable external onlyRole(BOND_ROLE) {
        uint256 totalStart;
        uint256 totalEnd;
        uint256 currSupply = _token.totalSupply();

        totalStart += calcLogIntegral(currSupply);

        totalEnd += calcLogIntegral(currSupply + num);

        uint256 nativeTokenPrice = totalEnd - totalStart;

        (bool success,) = payable(address(this)).call{value: nativeTokenPrice}("");
        require(success, "Low level Native Token transfer call failed");

        // The following predicate checks whether or not the
        // promotional period has ended
        if (promoEpoch < 20000) {
            _token.transfer(msg.sender, (180573542300000000000000 * 5) / 100000);
            promoEpoch += 1;
        }

        _token.mint(msg.sender, num);
    }

    receive() external payable {
        emit CollateralReceived(msg.sender, msg.value);
    }
}
