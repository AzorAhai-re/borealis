pragma solidity ^0.8.4;

import "./Token.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @title A title that should describe the contract/interface
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
contract BondingCurve is Initializable, AccessControlUpgradeable {
    address public _token;

    bytes32 public constant UNBOND_ROLE = keccak256("UNBOND");
    bytes32 public constant BOND_ROLE = keccak256("BOND");

    uint256 public constant targetSupply = 1355000000000000000000000;

    uint256 public constant eNume = 2718281828459045235;
    uint256 public constant eDeNom = 1000000000000000000;

    uint256 public constant startValueNume = 14760147601476015;
    uint256 public constant startValueDeNom = 1000000000000000000000000;

    uint256 public constant growthDenNom = 10000000000000000000000;

    function init(address token) external initializer {
        _token = token;
    }

    function calcLogIntegral(uint256 supply) pure internal returns (uint256) {
        return (
            (37 * (supply + growthDenNom * ((eNume ** (0 - supply / growthDenNom)) / eDeNom)))/ 100
        );
    }

    function calcRationalIntegral(uint256 supply) pure internal returns (uint256) {
        return (
            (startValueNume * targetSupply * supply - (supply ** 2) / 2) / startValueDeNom
        );
    }

    function bond() payable external onlyRole(BOND_ROLE) {
        Token token = Token(_token);

        uint256 EthUsdNume = 3_252_237;
        uint256 EthUsdDeNom = 100;

        uint256 usdAmount = (msg.value * EthUsdNume) / EthUsdDeNom;
        uint256 xcdAmount = (usdAmount * 271) / 100;

        uint256 totalStart = 0;
        uint256 totalEnd = 0;
        uint256 currSupply = token.totalSupply();
        uint256 newSupply = currSupply + xcdAmount;

        totalStart += calcLogIntegral(currSupply);
        totalStart += calcRationalIntegral(currSupply);

        totalEnd += calcLogIntegral(newSupply);
        totalEnd += calcRationalIntegral(newSupply);

        uint256 totalBonded = totalEnd - totalStart;

        token.mint(msg.sender, totalBonded);
    }
}
