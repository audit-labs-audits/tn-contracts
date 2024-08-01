// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { StablecoinHandler } from "telcoin-contracts/contracts/stablecoin/StablecoinHandler.sol";
import { IStablecoin } from "external/telcoin-contracts/interfaces/IStablecoin.sol";

/**
 * @title StablecoinManager
 * @author Robriks 📯️📯️📯️.eth
 * @notice A Telcoin Contract
 *
 * @notice This contract extends the StablecoinHandler which manages the minting and burning of stablecoins
 */
contract StablecoinManager is StablecoinHandler {
    using SafeERC20 for IERC20;

    struct XYZMetadata {
        address token;
        string name;
        string symbol;
        uint256 decimals;
    }

    error TokenArityMismatch();
    error LowLevelCallFailure();
    error InvalidXYZ(address token);

    event XYZAdded(address token);
    event XYZRemoved(address token);

    /// @custom:storage-location erc7201:telcoin.storage.StablecoinManager
    struct StablecoinManagerStorage {
        address[] _enabledXYZs;
    }

    // keccak256(abi.encode(uint256(keccak256("erc7201.telcoin.storage.StablecoinHandler")) - 1))
    //   & ~bytes32(uint256(0xff))
    bytes32 internal constant StablecoinHandlerStorageSlot =
        0x38361881985b0f585e6124dca158a3af102bffba0feb9c42b0b40825f41a3300;

    // keccak256(abi.encode(uint256(keccak256("erc7201.telcoin.storage.StablecoinManager")) - 1))
    //   & ~bytes32(uint256(0xff))
    bytes32 internal constant StablecoinManagerStorageSlot =
        0x77dc539bf9c224afa178d31bf07d5109c2b5c5e56656e49b25e507fec3a69f00;

    /// @dev Invokes `__Pausable_init()`
    function initialize(
        address admin_,
        address maintainer_,
        address[] calldata tokens_,
        eXYZ[] calldata eXYZs_
    )
        public
        initializer
    {
        if (tokens_.length != eXYZs_.length) revert TokenArityMismatch();

        __StablecoinHandler_init();
        // temporarily grant role to sender for use with the Arachnid Deterministic Deployment Factory
        _grantRole(MAINTAINER_ROLE, msg.sender);
        for (uint256 i; i < eXYZs_.length; ++i) {
            UpdateXYZ(tokens_[i], eXYZs_[i].validity, eXYZs_[i].maxSupply, eXYZs_[i].minSupply);
        }
        _revokeRole(MAINTAINER_ROLE, msg.sender);

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MAINTAINER_ROLE, maintainer_);
    }

    function UpdateXYZ(
        address token,
        bool validity,
        uint256 maxLimit,
        uint256 minLimit
    )
        public
        virtual
        override
        onlyRole(MAINTAINER_ROLE)
    {
        super.UpdateXYZ(token, validity, maxLimit, minLimit);

        _recordXYZ(token, validity);
    }

    /// @dev Fetches all currently valid stablecoin addresses
    function getEnabledXYZs() public view returns (address[] memory enabledXYZs) {
        StablecoinManagerStorage storage $ = _stablecoinManagerStorage();
        return $._enabledXYZs;
    }

    /// @dev Fetches all currently valid stablecoins with metadata for dynamic rendering by a frontend
    /// @notice Intended for use in a view context to save on RPC calls
    function getEnabledXYZsWithMetadata() public view returns (XYZMetadata[] memory enabledXYZMetadatas) {
        address[] memory enabledXYZs = getEnabledXYZs();

        enabledXYZMetadatas = new XYZMetadata[](enabledXYZs.length);
        for (uint256 i; i < enabledXYZs.length; ++i) {
            string memory name = IStablecoin(enabledXYZs[i]).name();
            string memory symbol = IStablecoin(enabledXYZs[i]).symbol();
            uint256 decimals = IStablecoin(enabledXYZs[i]).decimals();

            enabledXYZMetadatas[i] = XYZMetadata(enabledXYZs[i], name, symbol, decimals);
        }
    }

    /**
     *
     *   support
     *
     */

    /**
     * @notice Rescues crypto assets mistakenly sent to the contract.
     * @dev Allows for the recovery of both ERC20 tokens and native currency sent to the contract.
     * @param token The token to rescue. Use `address(0x0)` for native currency.
     * @param amount The amount of the token to rescue.
     */
    function rescueCrypto(IERC20 token, uint256 amount) public onlyRole(MAINTAINER_ROLE) {
        if (address(token) == address(0x0)) {
            // Native Currency
            (bool r,) = _msgSender().call{ value: amount }("");
            if (!r) revert LowLevelCallFailure();
        } else {
            // ERC20s
            token.safeTransfer(_msgSender(), amount);
        }
    }

    /**
     *
     *   internals
     *
     */
    function _recordXYZ(address token, bool validity) internal virtual {
        if (validity == true) {
            _addEnabledXYZ(token);
        } else {
            _removeEnabledXYZ(token);
        }
    }

    function _addEnabledXYZ(address token) internal {
        StablecoinManagerStorage storage $ = _stablecoinManagerStorage();
        $._enabledXYZs.push(token);

        emit XYZAdded(token);
    }

    function _removeEnabledXYZ(address token) internal {
        StablecoinManagerStorage storage $ = _stablecoinManagerStorage();

        // cache in memory
        address[] memory enabledXYZs = $._enabledXYZs;
        // find matching index in memory
        uint256 matchingIndex = type(uint256).max;
        for (uint256 i; i < enabledXYZs.length; ++i) {
            if (enabledXYZs[i] == token) matchingIndex = i;
        }

        // in the case no match was found, revert with info detailing invalid state
        if (matchingIndex == type(uint256).max) revert InvalidXYZ(token);

        // if match is not the final array member, write final array member into the matching index
        uint256 lastIndex = enabledXYZs.length - 1;
        if (matchingIndex != lastIndex) {
            $._enabledXYZs[matchingIndex] = enabledXYZs[lastIndex];
        }
        // pop member which is no longer relevant off end of array
        $._enabledXYZs.pop();

        emit XYZRemoved(token);
    }

    /// @notice Despite having similar names, `StablecoinManagerStorage` != `StablecoinHandlerStorage` !!
    function _stablecoinManagerStorage() internal pure returns (StablecoinManagerStorage storage $) {
        assembly {
            $.slot := StablecoinManagerStorageSlot
        }
    }

    /// @notice Despite having similar names, `StablecoinHandlerStorage` != `StablecoinManagerStorage` !!
    function _stablecoinHandlerStorage() internal pure returns (StablecoinHandlerStorage storage $) {
        assembly {
            $.slot := StablecoinHandlerStorageSlot
        }
    }
}
