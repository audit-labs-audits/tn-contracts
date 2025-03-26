// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity ^0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import { AxelarAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
import { AxelarAmplifierGatewayProxy } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGatewayProxy.sol";
import { BaseAmplifierGateway } from
    "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/BaseAmplifierGateway.sol";
import { Message, CommandType } from
"@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
import {
    WeightedSigner,
    WeightedSigners,
    Proof
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
import { InterchainTokenService } from
"@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import { InterchainProxy } from "@axelar-network/interchain-token-service/contracts/proxies/InterchainProxy.sol";
import { InterchainTokenDeployer } from
    "@axelar-network/interchain-token-service/contracts/utils/InterchainTokenDeployer.sol";
import { InterchainTokenFactory } from
"@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
import { InterchainToken } from
    "@axelar-network/interchain-token-service/contracts/interchain-token/InterchainToken.sol";
import { TokenManagerDeployer } from
"@axelar-network/interchain-token-service/contracts/utils/TokenManagerDeployer.sol";
import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { AxelarGasServiceProxy } from "../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { WTEL } from "../src/WTEL.sol";
import { RWTEL } from "../src/RWTEL.sol";
import { ExtCall } from "../src/interfaces/IRWTEL.sol";
import { Deployments } from "../deployments/Deployments.sol";
import { Create3Utils, Salts, ImplSalts } from "../deployments/Create3Utils.sol";

contract InterchainTokenServiceForkTest is Test, Create3Utils {
//     /// @dev Telcoin Network contracts
//     WTEL wTEL;
//     RWTEL rwTELImpl;
//     RWTEL rwTEL; 
//     // Axelar ITS contracts
//     Create3Deployer create3;
//     AxelarAmplifierGateway gatewayImpl;
//     AxelarAmplifierGateway gateway;
//     TokenManagerDeployer tokenManagerDeployer;
//     InterchainToken interchainTokenImpl;
//     // InterchainToken interchainToken; // InterchainProxy //todo use deployer?
//     InterchainTokenDeployer itDeployer;
//     TokenManager tokenManagerImpl;
//     TokenManager tokenManager;
//     TokenHandler tokenHandler;
//     AxelarGasService gasServiceImpl;
//     AxelarGasService gasService;
//     GatewayCaller gatewayCaller;
//     InterchainTokenService itsImpl;
//     InterchainTokenService its; // InterchainProxy
//     InterchainTokenFactory itFactoryImpl;
//     InterchainTokenFactory itFactory; // InterchainProxy

//     /// @dev Sepolia contracts
//     IAxelarGateway sepoliaGateway; // Axelar: "eth-sepolia"
//     IERC20 sepoliaTel;

//     address user;
//     string sourceChain;
//     string sourceAddress;
//     string destChain;
//     string destAddress;
//     string symbol;
//     uint256 amount;
//     bytes extCallData;
//     bytes payload;
//     bytes32 payloadHash;
//     string messageId;
//     Message[] messages;

//     //todo: trim constructor params since already deployed
//     // shared axelar constructor params
//     address admin = 0xc1612C97537c2CC62a11FC4516367AB6F62d4B23; // use deployments.admin
//     address deployerEOA = admin; //todo: separate deployer
//     address precalculatedITS;
//     address precalculatedITFactory;

//     // AxelarAmplifierGateway
//     string axelarId = "telcoin-network"; // used as `chainName_` for ITS
//     string routerAddress = "router"; //todo: devnet router
//     uint256 telChainId = 0x7e1;
//     bytes32 domainSeparator = keccak256(abi.encodePacked(axelarId, routerAddress, telChainId));
//     uint256 previousSignersRetention = 16;
//     uint256 minimumRotationDelay = 86_400; // default rotation delay is `1 day == 86400 seconds`
//     uint128 weight = 1; // todo: for testnet handle additional signers
//     address singleSigner = admin; // todo: for testnet increase signers
//     uint128 threshold = 1; // todo: for testnet increase threshold
//     bytes32 nonce = bytes32(0x0);
//     /// note: weightedSignersArray = [WeightedSigners([WeightedSigner(singleSigner, weight)], threshold, nonce)];
//     address gatewayOperator = admin; // todo: separate operator
//     bytes gatewaySetupParams; /// note: = abi.encode(gatewayOperator, weightedSignersArray);
//     address gatewayOwner = admin; // todo: separate owner

//     // AxelarGasService
//     address gasCollector = address(0xc011ec106); // todo: gas sponsorship key
//     address gsOwner = admin;
//     bytes gsSetupParams = ""; // unused

//     // InterchainTokenService
//     address itsOwner = admin; // todo: separate owner
//     address itsOperator = admin; // todo: separate operator
//     string chainName_ = axelarId;
//     string[] trustedChainNames = [chainName_]; //todo: change to supported chains
//     string[] trustedAddresses = [Strings.toString(uint256(uint160(admin)))]; //todo: change to remote ITS hub(s)
//     bytes itsSetupParams = abi.encode(itsOperator, chainName_, trustedChainNames, trustedAddresses);

//     // InterchainTokenFactory
//     address itfOwner = admin; // todo: separate owner

//     // rwTEL config
//     address consensusRegistry_; // TN system contract
//     address gateway_; // TN gateway
//     string symbol_ = "rwTEL";
//     string name_ = "Recoverable Wrapped Telcoin";
//     uint256 recoverableWindow_ = 604_800; // todo: confirm 1 week
//     address governanceAddress_ = address(0xda0); // todo: multisig/council/DAO address in prod
//     address baseERC20_ = address(wTEL);
//     uint16 maxToClean = type(uint16).max; // todo: revisit gas expectations; clear all relevant storage?
//     address rwtelOwner = admin; //todo: separate owner, multisig?

//     Deployments deployments;

//     string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
//     string TN_RPC_URL = vm.envString("TN_RPC_URL");
//     uint256 sepoliaFork;
//     uint256 tnFork;

//     function setUp() public {
//         string memory root = vm.projectRoot();
//         string memory path = string.concat(root, "/deployments/deployments.json");
//         string memory json = vm.readFile(path);
//         bytes memory data = vm.parseJson(json);
//         deployments = abi.decode(data, (Deployments));

//         wTEL = deployments.wTEL;
//         // deployments.rwTEL;
//         // deployments.everything
//     }

    // function setUpForkConfig() internal {
    //     // todo: currently replica; change to canonical Axelar sepolia gateway
    //     sepoliaGateway = IAxelarGateway(0xB906fC799C9E51f1231f37B867eEd1d9C5a6D472);
    //     sepoliaTel = IERC20(deployments.sepoliaTEL);
    //     tnGateway = AxelarAmplifierGateway(deployments.its.AxelarAmplifierGateway);
    //     tnWTEL = WTEL(payable(deployments.wTEL));
    //     tnRWTEL = RWTEL(payable(deployments.rwTEL));

    //     user = address(0x5d5d4d04B70BFe49ad7Aac8C4454536070dAf180);
    //     symbol = "TEL";
    //     amount = 100; // 1 tel

    //     //todo: deploy ITS contracts for fork testing
            //todo: write rwTEL to ITS create3 `interchainTokenAddress`
        // assertEq(its.interchainTokenAddress(canonicalInterchainTokenId), address(rwTEL));
    // }

    // its.contractCallValue(); // todo: decimals handling?

    //todo: before implementing these tests, create script functions & import
    // function test_fork_eth_registerCanonicalInterchainToken() public {
        //todo: create3 traces
        // ITokenManagerType.TokenManagerType tmType = ITokenManagerType.TokenManagerType.LOCK_UNLOCK;
        // bytes memory ethTMConstructorArgs = abi.encode(address(its), tmType, canonicalInterchainTokenId, abi.encode('', address(ethTEL)));
        // bytes32 _internalITSCreate3TokenIdSalt = keccak256(abi.encode(keccak256('its-interchain-token-id'), address(0x0), canonicalInterchainSalt));
        // address ethTokenManagerExpected = create3Address(create3, type(TokenManagerProxy).creationCode, ethTMConstructorArgs, address(its), _internalITSCreate3TokenIdSalt);
        // assertEq(address(ethTELTokenManager), ethTokenManagerExpected);


        // //todo: write to deployments.json
        // console2.logString("ITS linked token deploy salt for rwTEL:");
        // console2.logBytes32(canonicalInterchainSalt);
        // console2.logString("ITS canonical interchain token ID for rwTEL:");
        // console2.logBytes32(canonicalInterchainTokenId);
    // }

    // function test_fork_eth_linkToken() public {
        // // link destinationChain token (tnRWTEL) to local canonical token (ethTEL) by ITS tokenId
        // bytes memory linkParams = ""; // not used for canonical tokens
        // string memory destChain = "telcoin-network";
        // bytes memory destTokenAddress = AddressBytes.toBytes(address(rwTEL));
        // ITokenManagerType.TokenManagerType tmType = ITokenManagerType.TokenManagerType.LOCK_UNLOCK;
        // bytes32 tokenIdAgain =
        //     itFactory.linkToken{ value: gasValue }(canonicalInterchainSalt, destChain, destTokenAddress, tmType, linkParams, gasValue);
        // assertEq(rwTEL.canonicalInterchainTokenId(), tokenIdAgain);

        /// @dev Ethereum relayer detects ContractCall event and forwards to GMP API for hub inclusion on Axelar Network
        /// @dev Once registered with ITS Hub, `msg.sender` can use same salt to register and `linkToken()` on more chains


        //todo: below actions seem handled by registration with ITS hub from Ethereum
        // /// @notice In prod, these calls must be performed on TN as part of genesis
        // bytes32 linkedTokenSalt = itFactory.linkedTokenDeploySalt(rwTEL.SYSTEM_ADDRESS(), rwTEL.RWTEL_SALT());
        // assertEq(rwTEL.linkedTokenDeploySalt(), linkedTokenSalt);

        // // Register RWTEL canonical interchain tokenId && deploy TokenManager using Interchain Token Factory
        // bytes32 tokenId = itFactory.registerCustomToken(linkedTokenSalt, address(rwTEL), tmType, tmOperator);
        // assertEq(rwTEL.linkedTokenId(), tokenId);
    // }

    //todo: will this be handled by linkToken?
    // function test_fork_TN_registerInterchainToken() public {
    // ITokenManagerType.TokenManagerType tmType = ITokenManagerType.TokenManagerType.LOCK_UNLOCK;
        // bytes memory rwtelTMConstructorArgs = abi.encode(address(its), tmType, canonicalInterchainTokenId, abi.encode('', address(rwTEL)));
        // address rwtelTokenManagerExpected = create3Address(create3, type(TokenManagerProxy).creationCode, rwtelTMConstructorArgs, deployerEOA, canonicalInterchainSalt);
        // assertEq(rwtelTokenManager, rwtelTokenManagerExpected);
    // }

    /// @dev Inbound bridge tests

    // function test_fork_sepolia_interchainTransfer_TEL() public {
    //     //todo
    // }
    // function test_fork_sepolia_transmitInterchainTransfer_TEL() public {
    //     //todo
    // }

    // function test_fork_execute() public {
        // todo: payload seems constructed by its
        // bytesSrcAddr = AddressBytes.toBytes(srcAddr)
        // bytesDestAddr = AddressBytes.toBytes(RWTEL) //todo: should be user?
        // bytes memory nestedPayload = abi.encode(u256MessageType=TRANSFER, b32TokenId, bytesSrcAddr, bytesdestAddr,
        // u256amount, data);
        // bytes memory wrappedPayload = abi.encode(u256MessageType=FROM_HUB, originalSourceChain, nestedPayload);

        // GatewayCaller::approveContractCall()
        // its::execute(commandId, sourceChain, sourceAddress, wrappedPayload, wrappedPayloadHash)

        // vm.prank(user)
        // its.interchainTransfer();
    // }

    /// @dev Outbound bridge tests
    // function test_fork_TN_interchainTransfer_TEL() public {}
    // function test_fork_TN_transmitInterchainTransfer_TEL() public {
}
