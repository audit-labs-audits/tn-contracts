// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { ITokenDeployer } from '@axelar-network/axelar-cgp-solidity/contracts/interfaces/ITokenDeployer.sol';

import { BurnableMintableCappedERC20 } from './BurnableMintableCappedERC20.sol';

/// @notice Forked from Axelar dependency to support Solidity `^0.8.9` instead of `==0.8.9`
contract TokenDeployer is ITokenDeployer {
    function deployToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 cap,
        bytes32 salt
    ) external returns (address tokenAddress) {
        tokenAddress = address(new BurnableMintableCappedERC20{ salt: salt }(name, symbol, decimals, cap));
    }
}