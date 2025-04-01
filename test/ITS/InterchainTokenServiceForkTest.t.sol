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
import { Message, CommandType } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
import {
    WeightedSigner,
    WeightedSigners,
    Proof
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
import { InterchainTokenService } from "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import { InterchainProxy } from "@axelar-network/interchain-token-service/contracts/proxies/InterchainProxy.sol";
import { InterchainTokenDeployer } from
    "@axelar-network/interchain-token-service/contracts/utils/InterchainTokenDeployer.sol";
import { InterchainTokenFactory } from "@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
import { InterchainToken } from
    "@axelar-network/interchain-token-service/contracts/interchain-token/InterchainToken.sol";
import { TokenManagerDeployer } from "@axelar-network/interchain-token-service/contracts/utils/TokenManagerDeployer.sol";
import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { AxelarGasServiceProxy } from "../../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { WTEL } from "../../src/WTEL.sol";
import { RWTEL } from "../../src/RWTEL.sol";
import { ExtCall } from "../../src/interfaces/IRWTEL.sol";
import { Deployments } from "../../deployments/Deployments.sol";
import { Create3Utils, Salts, ImplSalts } from "../../deployments/utils/Create3Utils.sol";
import { ITSUtils } from "../../deployments/utils/ITSUtils.sol";

contract InterchainTokenServiceForkTest is Test, ITSUtils {
    // canonical chain config (sepolia or ethereum)
    // note that rwTEL interchainTokenSalt and interchainTokenId are the same as & derived from canonicalTEL
    bytes32 canonicalInterchainSalt; // salt derived from canonicalTEL is used for new interchain TEL tokens
    bytes32 canonicalInterchainTokenId; // tokenId derived from canonicalTEL is used for new interchain TEL
    TokenManager canonicalTELTokenManager;

    // Sepolia contracts
    IERC20 sepoliaTel;
    InterchainTokenService sepoliaITS;
    InterchainTokenFactory sepoliaITF;

    //todo: Ethereum contracts

    // Telcoin Network contracts
    WTEL wTEL;
    RWTEL rwTELImpl;
    RWTEL rwTEL;
    Create3Deployer create3;
    AxelarAmplifierGateway gatewayImpl;
    AxelarAmplifierGateway gateway;
    TokenManagerDeployer tokenManagerDeployer;
    InterchainToken interchainTokenImpl;
    InterchainTokenDeployer itDeployer;
    TokenManager tokenManagerImpl;
    TokenHandler tokenHandler;
    AxelarGasService gasServiceImpl;
    AxelarGasService gasService;
    GatewayCaller gatewayCaller;
    InterchainTokenService itsImpl;
    InterchainTokenService its; // InterchainProxy
    InterchainTokenFactory itFactoryImpl;
    InterchainTokenFactory itFactory; // InterchainProxy
    TokenManager canonicalRWTELTokenManager;

    Deployments deployments;

    //     string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    //     string TN_RPC_URL = vm.envString("TN_RPC_URL");
    //     uint256 sepoliaFork;
    //     uint256 tnFork;

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

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        // sepoliaTel = deployments.sepoliaTEL;
        // // sepoliaITS = deployments.its.sepolia.InterchainTokenService; //todo
        // // sepoliaITF = deployments.its.sepolia.InterchainTokenFactory;

        wTEL = WTEL(payable(deployments.wTEL));
        // rwTEL = deployments.rwTEL;
        // tnITS = deployments.tn.InterchainTokenService;
        // tnITF = deployments.tn.InterchainTokenFactory;
    }

    // function setUpSepoliaFork() internal {
    //     // todo: currently replica; change to canonical Axelar sepolia gateway
    // sepoliaGateway = IAxelarGateway(SEPOLIA_GATEWAY);
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
    // ITokenManagerType.TokenManagerType eth_tmType = ITokenManagerType.TokenManagerType.LOCK_UNLOCK;
    // bytes memory ethTMConstructorArgs = abi.encode(address(its), eth_tmType, canonicalInterchainTokenId,
    // abi.encode('',
    // address(ethTEL)));
    // bytes32 _internalITSCreate3TokenIdSalt = keccak256(abi.encode(keccak256('its-interchain-token-id'), address(0x0),
    // canonicalInterchainSalt));
    // address ethTokenManagerExpected = create3Address(create3, type(TokenManagerProxy).creationCode,
    // ethTMConstructorArgs,
    // address(its), _internalITSCreate3TokenIdSalt);
    // assertEq(address(ethTELTokenManager), ethTokenManagerExpected);

    // //todo: write to deployments.json
    // console2.logString("ITS linked token deploy salt for rwTEL:");
    // console2.logBytes32(canonicalInterchainSalt);
    // console2.logString("ITS canonical interchain token ID for rwTEL:");
    // console2.logBytes32(canonicalInterchainTokenId);
    // }

    // function test_fork_sepolia_deployRemoteCanonicalInterchainToken() public {
    /// @notice Because `deployRemoteCanonicalInterchainToken` will route a `MESSAGE_TYPE_LINK_TOKEN` through ITS hub
    /// that is guaranteed to revert when trying to redeploy genesis contracts, this call is skipped for testnet &
    /// mainnet

    // // Register canonical TEL metadata and deploy canonical TEL token manager on ethereum
    // uint256 gasValue = 100; // dummy gas value specified for multicalls
    // its.registerTokenMetadata{ value: gasValue }(canonicalTEL_, gasValue);
    // bytes32 canonicalInterchainSalt = itFactory.canonicalInterchainTokenDeploySalt(canonicalTEL_);
    // bytes32 canonicalInterchainTokenId = itFactory.registerCanonicalInterchainToken(canonicalTEL_);

    // // note that TN must have been added as a trusted chain to the Ethereum ITS contract
    // string memory destinationChain = TN_CHAIN_NAME;
    // vm.prank(itsOwner);
    // its.setTrustedAddress(destinationChain, ITS_HUB_ROUTING_IDENTIFIER);

    // // sends remote deploy message to ITS hub for rwTEL and its TokenManager on TN
    // // note this remote canonical interchain token step is for devnet only, obviated by testnet & mainnet genesis
    // bytes32 remoteCanonicalTokenId = itFactory.deployRemoteCanonicalInterchainToken{ value: gasValue }(canonicalTEL_,
    // destinationChain, gasValue);

    // /// @dev for devnet, relayer will forward link msg to TN thru ITS hub & use it to deploy rwtel tokenmanager

    // assertEq(remoteCanonicalTokenId, canonicalInterchainTokenId);

    //todo: asserts for devnet fork test & script
    // assertEq(remoteRwtelInterchainToken, expectedInterchainToken);
    // ITokenManager canonicalTELTokenManager = its.deployedTokenManager(canonicalInterchainTokenId);
    // assertEq(remoteRwtelTokenManager, address(canonicalTELTokenManager));
    // assertEq(remoteRwtelTokenManager, telTokenManagerAddress);
    // assertEq(rwtelExpectedInterchainToken, address(rwTEL)); //todo: genesis assertion
    // assertEq(rwtelExpectedTokenManager, address(rwTELTokenManager)); //todo: genesis assertion

    //todo: is below action handled by registration with ITS hub from Ethereum?
    // // Register RWTEL canonical interchain tokenId && deploy TokenManager using Interchain Token Factory
    // bytes32 tokenId = itFactory.registerCustomToken(linkedTokenSalt, address(rwTEL), tn_tmType, tmOperator);
    // assertEq(rwTEL.linkedTokenId(), tokenId);
    // }

    //todo: will this be handled by linkToken?
    // function test_fork_TN_registerInterchainToken() public {
    // ITokenManagerType.TokenManagerType tmType = ITokenManagerType.TokenManagerType.LOCK_UNLOCK;
    // bytes memory rwtelTMConstructorArgs = abi.encode(address(its), tmType, canonicalInterchainTokenId, abi.encode('',
    // address(rwTEL)));
    // address rwtelTokenManagerExpected = create3Address(create3, type(TokenManagerProxy).creationCode,
    // rwtelTMConstructorArgs, deployerEOA, canonicalInterchainSalt);
    // assertEq(rwtelTokenManager, rwtelTokenManagerExpected);
    // }

    /// @dev Inbound bridge tests

    // function test_fork_sepolia_interchainTransfer_TEL() public {
    //     //todo
    // }
    // function test_fork_sepolia_transmitInterchainTransfer_TEL() public {
    //     //todo
    // }

    // function test_tn_execute() public {
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
    // function test_fork_TN_interchainTransfer_TEL() public {
    // todo: test interchainTransfer on its && rwtel}
    // function test_fork_TN_transmitInterchainTransfer_TEL() public {}
    // todo: test transmitInterchainTransfer on its && rwtel}

    // function test_eth_execute() public {

    //todo: ITS genesis deploy config
    //todo: rwTEL genesis deploy config
    //todo: fuzz tests for rwTEL, TEL bridging, rwteltest.t.sol
    //todo: fork tests for TEL bridging
    //todo: incorporate RWTEL contracts to TN protocol on rust side

    //todo: update readme, npm instructions

    //todo: ERC20 bridging tests
    // function test_ERC20_interchainToken() public {
    //     // //todo: Non-TEL ERC20 InterchainToken asserts
    //     // assertEq(interchainToken.interchainTokenService(), address(its));
    //     // assertTrue(interchainToken.isMinter(address(its)));
    //     // assertEq(interchainToken.totalSupply(), totalSupply);
    //     // assertEq(interchainToken.balanceOf(address(rwTEL)), bal);
    //     // assertEq(interchainToken.nameHash(), nameHash);
    //     // assertEq(interchainToken.DOMAIN_SEPARATOR(), itDomainSeparator);
    // }
}
