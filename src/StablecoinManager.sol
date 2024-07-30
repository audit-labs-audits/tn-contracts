// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { StablecoinHandler } from "telcoin-contracts/contracts/stablecoin/StablecoinHandler.sol";

/**
 * @title StablecoinManager
 * @author Robriks 📯️📯️📯️.eth
 * @notice A Telcoin Contract
 *
 * @notice This contract extends the StablecoinHandler which manages the minting and burning of stablecoins
 */

    //todo: implement new `enabled` state rather than existing `validity`
    //todo: grant pauser, swapper, maintainer role to admin on deployment

contract StablecoinManager is StablecoinHandler {
    using SafeERC20 for IERC20;

    error LowLevelCallFailure();

    event ValidityUpdated(address token, bool newValidity);

    /// @custom:storage-location erc7201:telcoin.storage.StablecoinManager
    struct StablecoinManagerStorage {
        address[] _existingEXYZs;
    }

    // keccak256(abi.encode(uint256(keccak256("erc7201.telcoin.storage.StablecoinManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant StablecoinManagerStorageSlot = 0x77dc539bf9c224afa178d31bf07d5109c2b5c5e56656e49b25e507fec3a69f00;

    /// @notice Despite having similar names, `StablecoinManagerStorage` != `StablecoinHandlerStorage` !!
    function _getStablecoinManagerStorage() private pure returns (StablecoinManagerStorage storage $) {
        assembly {
            $.slot := StablecoinManagerStorageSlot
        }
    }

    /// @dev Invokes `__Pausable_init()`
    function initialize(address admin_) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        __StablecoinHandler_init();
    }

    /// @dev Sets only the `validity` struct member of the given stablecoin
    function updateValidity(address token, bool newValidity) public virtual onlyRole(MAINTAINER_ROLE) {
        StablecoinHandlerStorage storage $ = _getStablecoinHandlerStorage();
        $._eXYZs[token].validity = newValidity;
        
        emit ValidityUpdated(token, newValidity);
    }

    /// @dev Fetches all currently valid stablecoins for dynamic rendering by a frontend
    function getCurrentlyValidStablecoins() public view returns (address[] memory validXYZs) {
        StablecoinManagerStorage storage $ = _getStablecoinManagerStorage();
        // cache array in memory
        address[] memory existingEXYZs = $._existingEXYZs;

        // identify size of return array and mutate 
        uint256 validCounter;
        for (uint256 i; i < existingEXYZs.length; ++i) {
            if (isXYZ(existingEXYZs[i])) {
                ++validCounter;
            } else {
                existingEXYZs[i] = address(0x0);
            }
        }

        // populate return array
        validXYZs = new address[](validCounter);
        uint256 indexOffset;
        for (uint256 i; i < existingEXYZs.length; ++i) {
            if (existingEXYZs[i] == address(0x0)) {
                ++indexOffset;
            } else {
                validXYZs[i - indexOffset] = existingEXYZs[i];
            }

        }

    }
    
    /************************************************
     *   support
     ************************************************/

    /**
     * @notice Rescues crypto assets mistakenly sent to the contract.
     * @dev Allows for the recovery of both ERC20 tokens and native currency sent to the contract.
     * @param token The token to rescue. Use `address(0x0)` for native currency.
     * @param amount The amount of the token to rescue.
     */
     function rescueCrypto(
        IERC20 token,
        uint256 amount
    ) public onlyRole(MAINTAINER_ROLE) {
        if (address(token) == address(0x0)) {
            // Native Currency
            (bool r, ) = _msgSender().call{value: amount}("");
            if (!r) revert LowLevelCallFailure();
        } else {
            // ERC20s
            token.safeTransfer(_msgSender(), amount);
        }
    }
}