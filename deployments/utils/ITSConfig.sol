// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { LibString } from "solady/utils/LibString.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    WeightedSigner,
    WeightedSigners,
    Proof
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import { ITokenManagerType } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManagerType.sol";
import { InterchainTokenService } from "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import { InterchainTokenFactory } from "@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
import { AddressBytes } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressBytes.sol";
import { ITSUtils } from "./ITSUtils.sol";

abstract contract ITSConfig is ITSUtils {
    // chain constants
    string constant ITS_HUB_CHAIN_NAME = "axelar";
    string constant ITS_HUB_ROUTING_IDENTIFIER = "hub";
    string constant TN_CHAIN_NAME = "telcoin-network";
    bytes32 constant TN_CHAINNAMEHASH = keccak256(bytes(TN_CHAIN_NAME));
    string constant MAINNET_CHAIN_NAME = "Ethereum";
    bytes32 constant MAINNET_CHAINNAMEHASH = 0x564ccaf7594d66b1eaaea24fe01f0585bf52ee70852af4eac0cc4b04711cd0e2;
    address constant MAINNET_ITS = 0xB5FB4BE02232B1bBA4dC8f81dc24C26980dE9e3C;
    address constant MAINNET_GATEWAY = 0x4F4495243837681061C4743b74B3eEdf548D56A5;
    address constant MAINNET_TEL = 0x467Bccd9d29f223BcE8043b84E8C8B282827790F;
    string constant DEVNET_SEPOLIA_CHAIN_NAME = "core-ethereum";
    bytes32 constant DEVNET_SEPOLIA_CHAINNAMEHASH = 0xbef3ef21418c49cdf83043f00d3ffeebe97f404dee721f6a81a99b66d96d6724;
    address constant DEVNET_SEPOLIA_ITS = 0x77883201091c08570D55000AB32645b88cB96324;
    address constant DEVNET_SEPOLIA_GATEWAY = 0x7C60aA56482c2e78D75Fd6B380e1AdC537B97319;
    string constant TESTNET_SEPOLIA_CHAIN_NAME = "ethereum-sepolia";
    bytes32 constant TESTNET_SEPOLIA_CHAINNAMEHASH = 0x564ccaf7594d66b1eaaea24fe01f0585bf52ee70852af4eac0cc4b04711cd0e2;
    address constant TESTNET_SEPOLIA_ITS = 0xB5FB4BE02232B1bBA4dC8f81dc24C26980dE9e3C;
    address constant TESTNET_SEPOLIA_GATEWAY = 0xe432150cce91c13a887f7D836923d5597adD8E31;

    // message type constants; these serve as headers for ITS messages between chains
    uint256 constant MESSAGE_TYPE_INTERCHAIN_TRANSFER = 0;
    uint256 constant MESSAGE_TYPE_DEPLOY_INTERCHAIN_TOKEN = 1;
    // uint256 constant MESSAGE_TYPE_DEPLOY_TOKEN_MANAGER = 2;
    uint256 constant MESSAGE_TYPE_SEND_TO_HUB = 3;
    uint256 constant MESSAGE_TYPE_RECEIVE_FROM_HUB = 4;
    uint256 constant MESSAGE_TYPE_LINK_TOKEN = 5;
    uint256 constant MESSAGE_TYPE_REGISTER_TOKEN_METADATA = 6;

    // mutable fork contracts
    // Sepolia
    IERC20 sepoliaTEL;
    InterchainTokenService sepoliaITS;
    InterchainTokenFactory sepoliaITF;
    IAxelarGateway sepoliaGateway;

    //todo: Ethereum
    uint256 public constant telTotalSupply = 100_000_000_000e18;

    function _setUpDevnetConfig(address admin, address devnetTEL) internal virtual {
        // AxelarAmplifierGateway
        axelarId = TN_CHAIN_NAME;
        routerAddress = "router"; //todo: devnet router
        telChainId = 0x7e1;
        domainSeparator = keccak256(abi.encodePacked(axelarId, routerAddress, telChainId));
        previousSignersRetention = 16;
        minimumRotationDelay = 86_400;
        weight = 1; 
        threshold = 1;
        nonce = bytes32(0x0);
        ampdVerifierSigners.push(admin);  // todo: use ampd signer
        signerArray.push(WeightedSigner(ampdVerifierSigners[0], weight));
        // in memory since nested arrays within custom Solidity structs cannot be copied to storage
        WeightedSigners memory weightedSigners = WeightedSigners(signerArray, threshold, nonce);
        WeightedSigners[] memory weightedSignersArray = new WeightedSigners[](1);
        weightedSignersArray[0] = weightedSigners;
        gatewayOperator = admin;
        gatewaySetupParams = abi.encode(gatewayOperator, weightedSignersArray);
        gatewayOwner = admin;

        // AxelarGasService
        gasCollector = admin;
        gasValue = 30_000_000;
        gsOwner = admin;
        gsSetupParams = ""; // note: unused

        // InterchainTokenService
        itsOwner = admin;
        itsOperator = admin;
        chainName_ = TN_CHAIN_NAME;
        trustedChainNames.push(ITS_HUB_CHAIN_NAME); // leverage ITS hub to support remote chains
        trustedChainNames.push(DEVNET_SEPOLIA_CHAIN_NAME);
        trustedAddresses.push(ITS_HUB_ROUTING_IDENTIFIER);
        trustedAddresses.push(LibString.toHexString(DEVNET_SEPOLIA_ITS));
        itsSetupParams = abi.encode(itsOperator, chainName_, trustedChainNames, trustedAddresses);

        // InterchainTokenFactory
        itfOwner = admin;

        // rwTEL config
        canonicalTEL = devnetTEL;
        canonicalChainName_ = DEVNET_SEPOLIA_CHAIN_NAME;
        symbol_ = "rwTEL";
        name_ = "Recoverable Wrapped Telcoin";
        recoverableWindow_ = 604_800;
        governanceAddress_ = address(0xda0); //todo: select multisig for recoverable governance
        maxToClean = type(uint16).max;
        baseERC20_ = address(wTEL); 

        // rwTELTokenManager config
        rwtelTMType = ITokenManagerType.TokenManagerType.NATIVE_INTERCHAIN_TOKEN;
        operator = AddressBytes.toBytes(address(0xda0)); //todo: select operator who can set flowlimits
        tokenAddress = address(rwTEL);
        params = abi.encode(operator, tokenAddress);

        // stored for asserts
        abiEncodedWeightedSigners = abi.encode(weightedSigners);
    }

    /// @notice Transition to testnet handled by updating deployments.json, deploying fresh `testnetTEL` clone of canonical TEL
    function _setUpTestnetConfig(address testnetTEL) internal {
        // AxelarAmplifierGateway
        axelarId = TN_CHAIN_NAME;
        // routerAddress = ; //todo: testnet router
        telChainId = 0x7e1;
        domainSeparator = keccak256(abi.encodePacked(axelarId, routerAddress, telChainId));
        // previousSignersRetention = 16; // todo: 16 signers seems high; 0 means only current signers valid (security)
        minimumRotationDelay = 86_400;
        // weight = ; // todo: for testnet handle additional signers
        // threshold = ; // todo: for testnet increase threshold
        nonce = bytes32(0x0);
        // address signer = ; // todo: for testnet increase verifier instances (NVV)
        // signerArray.push(WeightedSigner(signer, weight));
        // in memory since nested arrays within custom Solidity structs cannot be copied to storage
        WeightedSigners memory weightedSigners = WeightedSigners(signerArray, threshold, nonce);
        WeightedSigners[] memory weightedSignersArray = new WeightedSigners[](1);
        weightedSignersArray[0] = weightedSigners;
        // gatewayOperator = ; //todo separate operator
        gatewaySetupParams = abi.encode(gatewayOperator, weightedSignersArray);
        // gatewayOwner = ; //todo

        // AxelarGasService
        // gasCollector = ; // todo: gas sponsorship key
        // gasValue == ; // todo: measure expected gas
        // gsOwner = ; //todo
        gsSetupParams = ""; // note: unused

        // "Ethereum" InterchainTokenService
        // itsOwner = ; // todo
        // itsOperator = ; // todo
        chainName_ = TN_CHAIN_NAME;
        trustedChainNames.push(ITS_HUB_CHAIN_NAME); // leverage ITS hub to support remote chains
        trustedAddresses.push(ITS_HUB_ROUTING_IDENTIFIER);
        itsSetupParams = abi.encode(itsOperator, chainName_, trustedChainNames, trustedAddresses);

        // InterchainTokenFactory
        // itfOwner = ; // todo: dedicated factory owner

        // rwTEL config
        canonicalTEL = testnetTEL;
        canonicalChainName_ = TESTNET_SEPOLIA_CHAIN_NAME;
        symbol_ = "rwTEL";
        name_ = "Recoverable Wrapped Telcoin";
        // recoverableWindow_ = 604_800; // todo: confirm 1 week
        // governanceAddress_ = ; // todo: multisig/council/DAO address in prod
        // maxToClean = type(uint16).max; // todo: revisit gas expectations; clear all relevant storage?
        baseERC20_ = address(wTEL);

        // stored for asserts
        abiEncodedWeightedSigners = abi.encode(weightedSigners);
    }
    
    //todo:
    // function _setUpMainnetConfig() internal {}
}
