// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./interfaces/IVault.sol";

/// @title A title that should describe the contract/interface
/// @author The name of the author
/// @notice Explain to an end user what this does
/// @dev Explain to a developer any extra details
contract Vault is Initializable, OwnableUpgradeable, IVault {
    using AddressUpgradeable for address;
    address public token;
    mapping(address => uint256) public balances;

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param tokenContractAddress a parameter just like in doxygen (must be followed by parameter name)
    function init(address tokenContractAddress) initializer external {
        require(AddressUpgradeable.isContract(msg.sender));
        token = tokenContractAddress;
    }

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param account a parameter just like in doxygen (must be followed by parameter name)
    /// @param amount a parameter just like in doxygen (must be followed by parameter name)
    function deposit(address account, uint256 amount) external override onlyOwner {
        _callOptionalReturn(
            token,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", account, address(this), amount
            )
        );
        balances[account] += amount;

        emit Deposited(account, amount);
    }

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param account a parameter just like in doxygen (must be followed by parameter name)
    /// @param amount a parameter just like in doxygen (must be followed by parameter name)
    function withdraw(address account, uint256 amount) external override onlyOwner {
        require(balances[account] >= amount, "insufficient `account` vault balance");
        _callOptionalReturn(
            token,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)", address(this), account, amount
            )
        );

        uint256 prevBalance = balances[account];
        unchecked {
            balances[account] = prevBalance - amount;
        }

        emit Withdrawn(account, amount);
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param tokenContract The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(address tokenContract, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = tokenContract.functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}
