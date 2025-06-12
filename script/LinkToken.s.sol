// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import { AxelarAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
import { BaseAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/BaseAmplifierGateway.sol";
import { Message, CommandType } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
import { AddressBytes } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressBytes.sol";
import { InterchainTokenService } from "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import { InterchainTokenFactory } from "@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { AxelarGasServiceProxy } from "../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LibString } from "solady/utils/LibString.sol";
import { WTEL } from "../src/WTEL.sol";
import { InterchainTEL } from "../src/InterchainTEL.sol";
import { Deployments, ITS } from "../deployments/Deployments.sol";
import { ITSConfig } from "../deployments/utils/ITSConfig.sol";

/// @title Interchain Token Service Genesis Config Generator
/// @notice Generates a yaml file comprising the storage slots and their values
/// Used by Telcoin-Network protocol to instantiate the contracts with required configuration at genesis

/// @dev Usage: `forge script script/LinkTokenInterchainTransfer.s.sol -vvvv`
contract LinkTokenInterchainTransfer is ITSConfig, Script {
    Deployments deployments;

    InterchainTokenService service;
    InterchainTokenFactory factory;
    string sourceChain;
    // string sourceAddressString;
    string destinationChain;
    address destinationAddress;
    // string destinationAddressString;

    function setUp() public {
        string memory path = string.concat(vm.projectRoot(), "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        service = InterchainTokenService(deployments.its.InterchainTokenService);
        factory = InterchainTokenFactory(deployments.its.InterchainTokenFactory);
        sourceChain = DEVNET_SEPOLIA_CHAIN_NAME;
        destinationChain = "telcoin";
        destinationAddress = governanceAddress_;

        /// @dev For testnet and mainnet genesis configs, use corresponding function
        _setUpDevnetConfig(deployments.admin, deployments.sepoliaTEL, deployments.wTEL, deployments.its.InterchainTEL);
    }

    function run() public {
        vm.startBroadcast(service.owner());

        service.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

        (bytes32 linkedTokenSalt, bytes32 linkedTokenId, TokenManager telTokenManager) = eth_registerCustomTokenAndLinkToken(
            originTEL,
            linker,
            destinationChain,
            deployments.its.InterchainTEL,
            originTMType,
            AddressBytes.toAddress(tmOperator),
            gasValue,
            factory
        );

        console2.logString(string.concat("linkedTokenSalt", LibString.toHexString(uint256(linkedTokenSalt), 32)));
        console2.logString(string.concat("linkedTokenId", LibString.toHexString(uint256(linkedTokenId), 32)));
        console2.logString(string.concat("tokenManager", LibString.toHexString(uint256(uint160(address(telTokenManager))), 20)));

        vm.stopBroadcast();
    }
}