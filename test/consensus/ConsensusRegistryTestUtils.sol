// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import { ConsensusRegistry } from "src/consensus/ConsensusRegistry.sol";
import { RWTEL } from "src/RWTEL.sol";

contract ConsensusRegistryTestUtils is ConsensusRegistry {
    ConsensusRegistry public consensusRegistryImpl;
    ConsensusRegistry public consensusRegistry;
    RWTEL public rwTEL;

    address public crOwner = address(0xc0ffee);
    address public validator1 = address(uint160(uint256(keccak256(abi.encode(0)))));
    address public validator2 = address(uint160(uint256(keccak256(abi.encode(1)))));
    address public validator3 = address(uint160(uint256(keccak256(abi.encode(2)))));
    address public validator4 = address(uint160(uint256(keccak256(abi.encode(3)))));
    address public validator5 = address(uint160(uint256(keccak256(abi.encode(4)))));

    ValidatorInfo validatorInfo1;
    ValidatorInfo validatorInfo2;
    ValidatorInfo validatorInfo3;
    ValidatorInfo validatorInfo4;

    ValidatorInfo[] initialValidators; // contains validatorInfo1-4

    address public sysAddress;
    bytes public validator5BlsPubkey = _createRandomBlsPubkey(5);

    uint256 public telMaxSupply = 100_000_000_000 ether;
    uint256 public stakeAmount = 1_000_000 ether;
    uint256 public minWithdrawAmount = 10_000 ether;
    // `OZ::ERC721Upgradeable::mint()` supports up to ~14_300 fuzzed mint iterations
    uint256 public MAX_MINTABLE = 14_000;

    constructor() {
        // deploy an RWTEL module
        rwTEL = new RWTEL(
            address(0xbabe),
            address(0xdead),
            bytes32(0x0),
            "chain",
            address(0xbeef),
            "test",
            "TEST",
            0,
            address(0x0),
            address(0x0),
            0
        );

        // provide initial validator set as the network will launch with at least four validators
        validatorInfo1 = ValidatorInfo(
            _createRandomBlsPubkey(1), validator1, uint32(0), uint32(0), ValidatorStatus.Active, false, false, uint8(0)
        );
        validatorInfo2 = ValidatorInfo(
            _createRandomBlsPubkey(2), validator2, uint32(0), uint32(0), ValidatorStatus.Active, false, false, uint8(0)
        );
        validatorInfo3 = ValidatorInfo(
            _createRandomBlsPubkey(3), validator3, uint32(0), uint32(0), ValidatorStatus.Active, false, false, uint8(0)
        );
        validatorInfo4 = ValidatorInfo(
            _createRandomBlsPubkey(4), validator4, uint32(0), uint32(0), ValidatorStatus.Active, false, false, uint8(0)
        );
        initialValidators.push(validatorInfo1);
        initialValidators.push(validatorInfo2);
        initialValidators.push(validatorInfo3);
        initialValidators.push(validatorInfo4);

        consensusRegistryImpl = new ConsensusRegistry();
    }

    function _createRandomBlsPubkey(uint256 seed) internal pure returns (bytes memory) {
        bytes32 seedHash = keccak256(abi.encode(seed));
        return abi.encodePacked(seedHash, seedHash, seedHash);
    }
}
