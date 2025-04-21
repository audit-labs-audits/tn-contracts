pragma solidity ^0.8.0;

import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";
import { IERC20MintableBurnable } from
    "@axelar-network/interchain-token-service/contracts/interfaces/IERC20MintableBurnable.sol";

/// @notice TNTokenManager minimally extends TokenManager to accept return values for mints/burns made to RWTEL
/// to convert decimals between custom-linked TEL ERC20s on remote chains & Telcoin-Network's native 18 decmals

contract TNTokenManager is TokenManager {
    constructor(address interchainTokenService_) TokenManager(interchainTokenService_) { }

    function mintTokenWithReturn(
        address tokenAddress_,
        address to,
        uint256 originAmount
    )
        external
        returns (uint256 mintedAmount)
    {
        (bool success, bytes memory minted) =
            tokenAddress_.call(abi.encodeWithSelector(IERC20MintableBurnable.mint.selector, to, originAmount));
        require(success, "TEL mint failed");

        mintedAmount = abi.decode(minted, (uint256));
    }

    function burnTokenWithReturn(
        address tokenAddress_,
        address from,
        uint256 nativeAmount
    )
        external
        returns (uint256 burnedAmount)
    {
        (bool success, bytes memory burned) =
            tokenAddress_.call(abi.encodeWithSelector(IERC20MintableBurnable.burn.selector, from, nativeAmount));
        require(success, "TEL mint failed");

        burnedAmount = abi.decode(burned, (uint256));
    }
}
