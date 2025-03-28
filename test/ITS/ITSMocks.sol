/// SPDX-License-Identifier MIT or Apache-2.0
pragma solidity ^0.8.26;

import { Create3AddressFixed } from "@axelar-network/interchain-token-service/contracts/utils/Create3AddressFixed.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";

contract HarnessCreate3FixedAddressForITS is Create3AddressFixed {
    function create3Address(bytes32 deploySalt) public view returns (address) {
        return _create3Address(deploySalt);
    }
}

/// @dev Read by ITS for metadata registration and used for tests
contract MockTEL is ERC20 {
    function decimals() public view virtual override returns (uint8) {
        return 2;
    }

    function name() public view virtual override returns (string memory) {
        return "Mock Telcoin";
    }

    function symbol() public view virtual override returns (string memory) {
        return "mockTEL";
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
