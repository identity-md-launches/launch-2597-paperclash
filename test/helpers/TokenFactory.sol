// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PAPERCLASH} from "../../src/PAPERCLASH.sol";

/// @dev Local test fixture, not a production launch factory.
contract TokenFactory {
    function deploy(bytes32 salt) external returns (PAPERCLASH) {
        return new PAPERCLASH{salt: salt}();
    }

    function move(PAPERCLASH token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

/// @dev An ERC-20 transfer must not invoke recipient code.
contract RejectingRecipient {
    fallback() external {
        revert("recipient callback invoked");
    }
}
