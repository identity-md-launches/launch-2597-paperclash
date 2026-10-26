// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title PAPERCLASH
/// @notice A fixed supply ERC-20: one billion tokens, each with 18 decimals.
/// @dev The immediate deployer receives the entire supply. For the IdentityMD
/// launch this is the factory, which handles subsequent distribution.
contract PAPERCLASH is ERC20 {
    /// @notice The entire supply, expressed in the token's smallest unit.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mint the entire supply once to the immediate deployer.
    constructor() ERC20("PAPERCLASH", "PAPERCLASH") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
