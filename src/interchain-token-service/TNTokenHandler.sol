// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from '@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IERC20.sol';
import { ITokenManager } from '@axelar-network/interchain-token-service/contracts/interfaces/ITokenManager.sol';
import { ITokenManagerProxy } from '@axelar-network/interchain-token-service/contracts/interfaces/ITokenManagerProxy.sol';
import { TokenHandler } from './TokenHandler.sol';

/// @notice Minimally forks Axelar ITS TokenHandler v2.1.0, adding TEL-specific branches to handle cross chain decimals 
/// by accepting mint/burn return values within `giveToken` and `takeToken` fns, using `_mintTEL`, and `_burnTEL`
import { TNTokenManager } from "./TNTokenManager.sol";

contract TNTokenHandler is TokenHandler {
    bytes32 public immutable telInterchainTokenId;

    constructor(bytes32 telInterchainTokenId_) {
        telInterchainTokenId = telInterchainTokenId_;
    }

    function giveToken(bytes32 tokenId, address to, uint256 amount) external virtual override returns (uint256, address) {
        address tokenManager = _create3Address(tokenId);

        (uint256 tokenManagerType, address tokenAddress) = ITokenManagerProxy(tokenManager).getImplementationTypeAndTokenAddress();

        _migrateToken(tokenManager, tokenAddress, tokenManagerType);

        /// @dev Track the flow amount being received via the message
        ITokenManager(tokenManager).addFlowIn(amount);

        if (
            tokenManagerType == uint256(TokenManagerType.NATIVE_INTERCHAIN_TOKEN) ||
            tokenManagerType == uint256(TokenManagerType.MINT_BURN) ||
            tokenManagerType == uint256(TokenManagerType.MINT_BURN_FROM)
        ) {
            if (tokenId == telInterchainTokenId) {
                amount = _mintTEL(TNTokenManager(tokenManager), tokenAddress, to, amount);
            } else {
                _mintToken(ITokenManager(tokenManager), tokenAddress, to, amount);
            }
        } else if (tokenManagerType == uint256(TokenManagerType.LOCK_UNLOCK)) {
            _transferTokenFrom(tokenAddress, tokenManager, to, amount);
        } else if (tokenManagerType == uint256(TokenManagerType.LOCK_UNLOCK_FEE)) {
            amount = _transferTokenFromWithFee(tokenAddress, tokenManager, to, amount);
        } else {
            revert UnsupportedTokenManagerType(tokenManagerType);
        }

        return (amount, tokenAddress);
    }

    /**
     * @notice This function takes token from a specified address to the token manager.
     * @param tokenId The tokenId for the token.
     * @param tokenOnly can only be called from the token.
     * @param from The address to take tokens from.
     * @param amount The amount of token to take.
     * @return uint256 The amount of token actually taken, which could be different for certain token type.
     */
    // slither-disable-next-line locked-ether
    function takeToken(bytes32 tokenId, bool tokenOnly, address from, uint256 amount) external virtual override payable returns (uint256) {
        address tokenManager = _create3Address(tokenId);
        (uint256 tokenManagerType, address tokenAddress) = ITokenManagerProxy(tokenManager).getImplementationTypeAndTokenAddress();

        if (tokenOnly && msg.sender != tokenAddress) revert NotToken(msg.sender, tokenAddress);

        _migrateToken(tokenManager, tokenAddress, tokenManagerType);

        if (
            tokenManagerType == uint256(TokenManagerType.NATIVE_INTERCHAIN_TOKEN) || tokenManagerType == uint256(TokenManagerType.MINT_BURN)
        ) {
            if (tokenId == telInterchainTokenId) {
                amount = _burnTEL(TNTokenManager(tokenManager), tokenAddress, from, amount);
            } else {
                _burnToken(ITokenManager(tokenManager), tokenAddress, from, amount);
            }
        } else if (tokenManagerType == uint256(TokenManagerType.MINT_BURN_FROM)) {
            _burnTokenFrom(tokenAddress, from, amount);
        } else if (tokenManagerType == uint256(TokenManagerType.LOCK_UNLOCK)) {
            _transferTokenFrom(tokenAddress, from, tokenManager, amount);
        } else if (tokenManagerType == uint256(TokenManagerType.LOCK_UNLOCK_FEE)) {
            amount = _transferTokenFromWithFee(tokenAddress, from, tokenManager, amount);
        } else {
            revert UnsupportedTokenManagerType(tokenManagerType);
        }

        /// @dev Track the flow amount being sent out as a message
        ITokenManager(tokenManager).addFlowOut(amount);

        return amount;
    }

    function _mintTEL(TNTokenManager telTokenManager, address tokenAddress_, address to, uint256 amount) internal returns (uint256) {
        return telTokenManager.mintTokenWithReturn(tokenAddress_, to, amount);
    }

    function _burnTEL(TNTokenManager telTokenManager, address tokenAddress_, address from, uint256 amount) internal returns (uint256) {
        return telTokenManager.burnTokenWithReturn(tokenAddress_, from, amount);
    }
}