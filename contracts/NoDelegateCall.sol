// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title Prevents delegatecall to a contract, derived from UniSwap's NoDelegateCall contract
/// @notice Base contract that provides a modifier for preventing delegatecall to methods in a child contract
abstract contract NoDelegateCall is Initializable {
    /// @dev The original address of this contract
    address private original;
    /// @dev Intermediary `initialized` checker for setting original contract address
    bool private _initialized;

    function _init_NDC() initializer internal {
        if (!_initialized){
            _setOriginalContract();
            _initialized = true;
        }
    }

    function _setOriginalContract() onlyInitializing internal {
        original = address(this);
    }

    /// @dev Private method is used instead of inlining into modifier because modifiers are copied into each method,
    ///     and the use of immutable means the address bytes are copied in every place the modifier is used.
    function checkNotDelegateCall() private view {
        require(address(this) == original);
    }

    /// @notice Prevents delegatecall into the modified method
    modifier noDelegateCall() {
        checkNotDelegateCall();
        _;
    }

    // * this contract has been modified to make it upgrade safe
    // the mutability of the `original` address is thus possible, however, it
    // can only be mutated once in storage by a contract account
}