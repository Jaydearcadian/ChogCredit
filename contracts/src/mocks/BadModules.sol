// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// TEST ONLY. Credit-module look-alikes that misbehave in the ways a bound module could.
// hasPendingOperation(bytes32) selector = 0x4c4717d2

/// @dev Has code but implements nothing (every call hits the fallback and returns no data).
contract BadNoFunctions {
    fallback() external {}
}

/// @dev Answers every call with two words.
contract BadWrongSize {
    fallback() external {
        assembly {
            mstore(0x00, 0)
            mstore(0x20, 0)
            return(0x00, 0x40)
        }
    }
}

/// @dev debtOf answers 0; hasPendingOperation answers 2, which is not a bool.
contract BadBool {
    fallback() external {
        assembly {
            mstore(0x00, 0)
            if eq(shr(224, calldataload(0)), 0x4c4717d2) { mstore(0x00, 2) }
            return(0x00, 0x20)
        }
    }
}

/// @dev Switchable behaviour: 0 healthy, 1 revert, 2 two words, 3 huge return, 4 bool == 2 on hasPendingOperation.
contract BadSwitchable {
    uint256 public mode;

    function setMode(uint256 m) external {
        mode = m;
    }

    fallback() external {
        uint256 m = mode;
        assembly {
            switch m
            case 1 { revert(0, 0) }
            case 2 {
                mstore(0x00, 0)
                mstore(0x20, 0)
                return(0x00, 0x40)
            }
            case 3 { return(0x00, 0x100000) } // ~1 MB
            case 4 {
                mstore(0x00, 0)
                if eq(shr(224, calldataload(0)), 0x4c4717d2) { mstore(0x00, 2) }
                return(0x00, 0x20)
            }
            default {
                mstore(0x00, 0)
                return(0x00, 0x20)
            }
        }
    }
}
