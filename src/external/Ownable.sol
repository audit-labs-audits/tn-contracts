// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IOwnable } from '@axelar-network/axelar-cgp-solidity/contracts/interfaces/IOwnable.sol';

/// @notice Forked from Axelar dependency to support Solidity `^0.8.9` instead of `==0.8.9`
abstract contract Ownable is IOwnable {
    address public owner;

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        if (owner != msg.sender) revert NotOwner();

        _;
    }

    function transferOwnership(address newOwner) external virtual onlyOwner {
        if (newOwner == address(0)) revert InvalidOwner();

        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}