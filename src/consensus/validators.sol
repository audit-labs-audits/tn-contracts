// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// spec:
 // store validator pubkeys (ecdsa, not bls)
 // recover signatures from those validator pubkeys to store and to verify
 // func to return random validator set from prevrandao and numvalidators
 // reward/slash schema (merkleized, rewards go to staking contract)

// questions:
 // how long to store epoch info? ringbuffer(committee, numBlocksInEpoch)
 // how long in future to use PREVRANDAO (for security, validators have limited control of it)

/**
 * @title ConsensusRegistry
 * @author Telcoin Association
 * @notice A Telcoin Contract
 *
 * @notice This contract manages consensus validator external keys, staking, and committees
 * @dev This contract should be deployed to a predefined system address for use with system calls
 */
contract ConsensusRegistry is UUPSUpgradeable, OwnableUpgradeable {

    error OnlySystemCall(address invalidCaller);
    error LowLevelCallFailure();
    error NotValidator(address pubkey);
    error AlreadyDefined(address pubkey);
    error InvalidProof(bytes proof);
    error InsufficientStake(uint256 stakeAmount);
    error InsufficientRewards(uint256 withdrawAmount);

    event ValidatorAdded(address pubkey);
    event ValidatorRemoved(address pubkey);

    enum ValidatorStatus {
        Undefined,
        PendingActivation,
        Active,
        Offline,
        PendingExit,
        Exited
    }

    struct ValidatorInfo {
        address pubkey;
        uint32 activationEpoch; // uint32 provides ~22000yr for 160s epochs (5s rounds)
        uint32 exitEpoch;
        bytes6 unused; // can be used for other data as well as expanded against activation and exit members
        ValidatorStatus currentStatus;
    }

    /// @custom:storage-location erc7201:telcoin.storage.ConsensusRegistry
    struct ConsensusRegistryStorage {
        uint256 minStakeAmount;
        uint256 minWithdrawAmount;
        uint32 currentEpoch; // can be resized
        mapping (address => uint256) validatorInfosIndex;
        ValidatorInfo[] validatorInfos;
        ValidatorInfo[] currentCommittee;
    }

    // keccak256(abi.encode(uint256(keccak256("erc7201.telcoin.storage.ConsensusRegistry")) - 1))
    //   & ~bytes32(uint256(0xff))
    bytes32 internal constant ConsensusRegistryStorageSlot =
        0xaf33537d204b7c8488a91ad2a40f2c043712bad394401b7dd7bd4cb801f23100;

    address public constant SYSTEM_ADDRESS = address(0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE);

    /// @notice Voting Validator Committee changes once every epoch (== 32 rounds)
    /// @notice Can only be called in a `syscall` context
    function finalizeEpoch(uint256 currentEpochBlocks) external returns (address[] memory newCommittee) {
        if (msg.sender != SYSTEM_ADDRESS) revert OnlySystemCall(msg.sender);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        // increment `currentEpoch`, cache in memory for use in resolving validators pending activation & exit
        uint256 newCurrentEpoch = ++$.currentEpoch;
        _updateValidatorSet($, newCurrentEpoch);

        // TODO: should offline validators be given the chance to come back online in the next epoch?
        uint256 numActive = _getValidators($, ValidatorStatus.Active).length;

        // determine new committee
        newCommittee = _deriveVoterCommittee(numActive);
        // store epoch info (committee, currentEpochBlocks)
    }



    function getValidators(ValidatorStatus status) public returns (ValidatorInfo[] memory) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        return _getValidators($, status);
    }

    /**
     *
     *   staking
     *
     */

    function stake() external payable {
        // require caller is a verified protocol validator
        // require msg.value >= minStakeAmount
        // add caller to pending validator queue
    }

    function claimStakeRewards() external {
        // require caller is verified protocol validator
        // require caller is a known `ValidatorInfo`
        // calculate rewards? or should that be written via syscall in every `finalizeEpoch()`
        // require rewards > minWithdrawAmount
        // wipe ledger
        // send rewards
    }

    function exit() external {
        // require caller is a known `ValidatorInfo` with `active || offline` status
        // enter validator in exit queue (will be ejected in 1.x epochs)
    }

    /**
     *
     *   internals
     *
     */

    function _updateValidatorSet(ConsensusRegistryStorage storage $, uint256 currentEpoch) internal {
        ValidatorInfo[] storage validators = $.validatorInfos;
        for (uint256 i; i < validators.length; ++i) {
            // cache validator in memory (but write to storage member)
            ValidatorInfo memory currentValidator = validators[i];

            if (currentValidator.currentStatus == ValidatorStatus.PendingActivation) {
                // activate validators which have waited at least a full epoch
                if (currentValidator.activationEpoch == currentEpoch) {
                    validators[i].currentStatus = ValidatorStatus.Active;
                }
            } else if (currentValidator.currentStatus == ValidatorStatus.PendingExit) {
                // eject validators which have waited at least a full epoch
                if (currentValidator.exitEpoch == currentEpoch) {
                    validators[i].currentStatus = ValidatorStatus.Exited;
                }
            }
        }
    }

    function _deriveVoterCommittee(uint256 committeeSize) internal returns (address[] memory newCommittee) {
        // use numValidators and `PREVRANDAO` value one epoch in the future as random seed
        /// @dev This would not be sufficient randomness on Ethereum but may be on Telcoin due to unpredictability of parallel block building
    }

    function _queuePendingValidator(address pubkey) internal {
        // ensure validator is legitimate
        // ensure validator is staked
        // require caller is validator || owner (no owner in prod)
    }

    function _getValidators(ConsensusRegistryStorage storage $, ValidatorStatus status) internal view returns (ValidatorInfo[] memory) {
        ValidatorInfo[] memory allValidators = $.validatorInfos;

        if (status == ValidatorStatus.Undefined) {
        // provide undefined status `== uint8(0)` to get full validator list of any status
            return allValidators;
        } else {
            // identify number of validators matching provided `status`
            uint256 numMatches;
            for (uint256 i; i < allValidators.length; ++i) {
                if (allValidators[i].currentStatus == status) ++numMatches;
            }

            // populate new array once length has been identified
            ValidatorInfo[] memory validatorsMatched = new ValidatorInfo[](numMatches);
            uint256 indexCounter;
            for (uint256 i; i < allValidators.length; ++i) {
                if (allValidators[i].currentStatus == status) {
                    validatorsMatched[indexCounter] = allValidators[i];
                    ++indexCounter;
                }
            }

            return validatorsMatched;
        }
    }

    function _consensusRegistryStorage() internal pure returns (ConsensusRegistryStorage storage $) {
        assembly {
            $.slot := ConsensusRegistryStorageSlot
        }
    }

    /**
     *
     *   upgradeability (devnet, testnet)
     *
     */

    function initialize() external initializer {
        // store initial validator set
    }

    /// @notice Only the owner may perform an upgrade
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner { }
}