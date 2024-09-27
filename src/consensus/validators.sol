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
 // how long to store known validators after they exit? expected num validators is low, but eventually array grows too big
 
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
    error InvalidStakeAmount(uint256 stakeAmount);
    error InvalidStatus(ValidatorStatus status);
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

    struct EpochInfo {
        uint256[] committeeIndices;
        uint16 numBlocks; // up to 65536 blocks per epoch - is this enough?
    }

    /// @custom:storage-location erc7201:telcoin.storage.ConsensusRegistry
    struct ConsensusRegistryStorage {
        uint256 minStakeAmount;
        uint256 minWithdrawAmount;
        uint32 currentEpoch; // can be resized
        mapping (uint256 => EpochInfo) epochInfo;
        // todo: handle 0th index in `validatorInfosIndex`
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
    function finalizeEpoch(uint16 currentEpochBlocks) external returns (uint256[] memory newCommittee) {
        if (msg.sender != SYSTEM_ADDRESS) revert OnlySystemCall(msg.sender);

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        // increment `currentEpoch`, cache in memory for use in resolving validators pending activation & exit
        uint256 newEpoch = ++$.currentEpoch;
        _updateValidatorSet($, newEpoch);

        // TODO: should offline validators be given the chance to come back online in the next epoch?
        uint256 numActiveValidators = _getValidators($, ValidatorStatus.Active).length;

        // determine new committee
        newCommittee = _updateVoterCommittee($, currentEpochBlocks, newEpoch, numActiveValidators);
        // store epoch info (committee, currentEpochBlocks)
    }

    function _updateVoterCommittee(ConsensusRegistryStorage storage $, uint16 currentEpochBlocks, uint256 newEpoch, uint256 numActiveValidators) internal returns (uint256[] memory newCommittee) {
        // store previous epoch info now that it is known
        $.epochInfo[newEpoch - 1].numBlocks = currentEpochBlocks;

        newCommittee = _deriveVoterCommittee(numActiveValidators);
        $.epochInfo[newEpoch].committeeIndices = newCommittee;
    }

    function getValidators(ValidatorStatus status) public view returns (ValidatorInfo[] memory) {
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        return _getValidators($, status);
    }

    /**
     *
     *   staking
     *
     */

    function stake() external payable {
        // require caller is a verified protocol validator - how to do this?

        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();
        if (msg.value != $.minStakeAmount) revert InvalidStakeAmount(msg.value);
        
        uint256 validatorIndex = $.validatorInfosIndex[msg.sender];
        if (validatorIndex == 0) { // caller is a new validator
            // pull length before it is incremented by `_queuePendingAction()`
            validatorIndex = $.validatorInfos.length;
        } else { // caller is a previously known validator
            ValidatorInfo memory existingValidator = $.validatorInfos[validatorIndex];
            // for already known validators, only `Exited` status is valid logical branch
            if (existingValidator.currentStatus != ValidatorStatus.Exited) revert InvalidStatus(existingValidator.currentStatus);
        }

        // add caller to pending validator queue
        _queuePendingAction($, validatorIndex, ValidatorStatus.PendingActivation);
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
        ConsensusRegistryStorage storage $ = _consensusRegistryStorage();

        // require caller is a known `ValidatorInfo` with `active || offline` status
        uint256 validatorIndex = $.validatorInfosIndex[msg.sender];
        //todo: there exists a 0th index; must be handled
        if (validatorIndex == 0) revert NotValidator(msg.sender);
        ValidatorInfo memory validator = $.validatorInfos[validatorIndex];
        if (validator.currentStatus != ValidatorStatus.Active || validator.currentStatus != ValidatorStatus.Offline) {
            revert InvalidStatus(validator.currentStatus);
        }

        // enter validator in exit queue (will be ejected in 1.x epochs)
        _queuePendingAction($, validatorIndex, ValidatorStatus.PendingExit);
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

    /// @dev For a BFT system to tolerate `n` faulty or malicious nodes, it requires `>= 3n + 1` total nodes
    /// This means that the committee size should be such that it can tolerate a reasonable value for `n`
    /// @param newCommittee Returned array of validator indices to serve as the next epoch's voting committee
    function _deriveVoterCommittee(uint256 numActiveValidators) internal view returns (uint256[] memory newCommittee) {
        uint256 committeeSize;
        if (numActiveValidators <= 4) {
            committeeSize = numActiveValidators;
        } else {
            // calculate floored number of tolerable faults for given active node count
            uint256 n = numActiveValidators / 3;

            // size committee based on the 2n+1 rule
            committeeSize = 3 * n + 1;
        }

        newCommittee = new uint256[](committeeSize);

        // use hashed `PREVRANDAO` value as randomness seed
        /// @notice This would not be sufficient randomness on Ethereum but may be on Telcoin due to unpredictability of parallel block building
        bytes32 seed = keccak256(abi.encode(block.prevrandao));
        // identify randomized indices within `validatorInfos` to populate `newCommittee`
        uint256[] memory selectedIndices = new uint256[](numActiveValidators);
        uint256 selectedCount;
        for (uint256 i; i < committeeSize; i++) {
            bool unique;
            uint256 randomIndex;

            // ensure unique index
            do {
                unique = true;
                randomIndex = uint256(keccak256(abi.encode(seed, i, selectedCount))) % numActiveValidators;

                // check if the index is already used
                for (uint256 j = 0; j < selectedCount; j++) {
                    if (selectedIndices[j] == randomIndex) {
                        unique = false;
                        break;
                    }
                }
            } while (!unique);

            // add unique index to array, increment counter
            selectedIndices[selectedCount] = randomIndex;
            selectedCount++;

            // Add the unique index to the new committee
            newCommittee[i] = randomIndex;
        }
    }

    function _queuePendingAction(ConsensusRegistryStorage storage $, uint256 validatorIndex, ValidatorStatus status) internal {
        if (status == ValidatorStatus.PendingActivation) {
            // push to array (increments length)
            uint32 activationEpoch = $.currentEpoch + 2;
            $.validatorInfos.push(ValidatorInfo(msg.sender, activationEpoch, uint32(0), bytes6(0), status));
        } else if (status == ValidatorStatus.PendingExit) {
            // mark as Exited but do not delete from array
            $.validatorInfos[validatorIndex].currentStatus = status;
        }
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