// SPDX-License-Identifier: MIT or Apache-2.0
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
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
import { AddressBytes } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressBytes.sol";
import { Create3AddressFixed } from "@axelar-network/interchain-token-service/contracts/utils/Create3AddressFixed.sol";
import { InterchainTokenService } from "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
import { InterchainProxy } from "@axelar-network/interchain-token-service/contracts/proxies/InterchainProxy.sol";
import { TokenManagerProxy } from "@axelar-network/interchain-token-service/contracts/proxies/TokenManagerProxy.sol";
import { InterchainTokenDeployer } from
    "@axelar-network/interchain-token-service/contracts/utils/InterchainTokenDeployer.sol";
import { InterchainTokenFactory } from "@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
import { InterchainToken } from
    "@axelar-network/interchain-token-service/contracts/interchain-token/InterchainToken.sol";
import { TokenManagerDeployer } from "@axelar-network/interchain-token-service/contracts/utils/TokenManagerDeployer.sol";
import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";
import { ITokenManager } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManager.sol";
import { ITokenManagerType } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManagerType.sol";
import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
import { AxelarGasServiceProxy } from "../../../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { LibString } from "solady/utils/LibString.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { WTEL } from "../../../src/WTEL.sol";
import { RWTEL } from "../../../src/RWTEL.sol";
import { ExtCall } from "../../../src/interfaces/IRWTEL.sol";
import { Create3Utils, Salts, ImplSalts } from "../../../deployments/Create3Utils.sol";
import { Deployments } from "../../../deployments/Deployments.sol";
import { ITSConfig } from "test/ITS/utils/ITSConfig.sol";

/// @dev Usage: `forge script script/testnet/deploy/TestnetDeployITS.s.sol \
/// --rpc-url $TN_RPC_URL -vvvv --private-key $ADMIN_PK`
// To verify RWTEL: `forge verify-contract <address> src/RWTEL.sol:RWTEL \
// --rpc-url $TN_RPC_URL --verifier sourcify --compiler-version 0.8.26 --num-of-optimizations 200`
contract TestnetDeployITS is Script, Create3Utils, ITSConfig {
    // TN contracts
    WTEL wTEL; // already deployed
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

    // note that rwTEL interchainTokenSalt and interchainTokenId are the same as & derived from canonicalTEL
    bytes32 canonicalInterchainSalt; // salt derived from canonicalTEL is used for new interchain TEL tokens
    bytes32 canonicalInterchainTokenId; // tokenId derived from canonicalTEL is used for new interchain TEL TokenManagers
    TokenManager canonicalTELTokenManager;

    Deployments deployments;
    address admin;
    address rwtelOwner;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        /// @dev For testnet, a developer admin address serves as governanceAddress_
        admin = deployments.admin;
        canonicalTEL = deployments.sepoliaTEL;

        // AxelarAmplifierGateway
        axelarId = TN_CHAIN_NAME;
        // routerAddress; // todo: devnet router
        telChainId = 0x7e1;
        domainSeparator = keccak256(abi.encodePacked(axelarId, routerAddress, telChainId));
        previousSignersRetention = 16; 
        minimumRotationDelay = 86_400;
        weight = 1;
        // singleSigner; // todo: use ampd signer
        threshold = 1;
        nonce = bytes32(0x0);
        /// note: weightedSignersArray = [WeightedSigners([WeightedSigner(singleSigner, weight)], threshold, nonce)];
        gatewayOperator = admin;
        gatewaySetupParams;
        /// note: = abi.encode(gatewayOperator, weightedSignersArray);
        gatewayOwner = admin;

        // AxelarGasService
        gasCollector = admin;
        gsOwner = admin;
        gsSetupParams = ""; // note: unused

        // InterchainTokenService
        itsOwner = admin;
        itsOperator = admin;
        chainName_ = TN_CHAIN_NAME;
        trustedChainNames.push(ITS_HUB_CHAIN_NAME); // leverage ITS hub to support remote chains
        trustedChainNames.push(DEVNET_SEPOLIA_CHAIN_NAME);
        trustedAddresses.push(ITS_HUB_ROUTING_IDENTIFIER);
        trustedAddresses.push(ITS_HUB_ROUTING_IDENTIFIER);
        itsSetupParams = abi.encode(itsOperator, chainName_, trustedChainNames, trustedAddresses);

        // InterchainTokenFactory
        itfOwner = admin;

        // rwTEL config
        canonicalChainName_ = DEVNET_SEPOLIA_CHAIN_NAME;
        name_ = "Recoverable Wrapped Telcoin"; // used only for assertion
        symbol_ = "rwTEL"; // used only for assertion
        recoverableWindow_ = 604_800; // ~1 week; Telcoin Network blocktime is ~1s
        governanceAddress_ = admin; // multisig/council/DAO address in prod
        baseERC20_ = deployments.wTEL;
        maxToClean = type(uint16).max; // gas is not expected to be an obstacle; clear all relevant storage

        rwtelOwner = admin; // note: devnet only
    }

    function run() public {
        // vm.startBroadcast();

        // rwTELImpl = new RWTEL{ salt: rwtelImplSalt }(
        //     address(0xbabe),
        //     "chain",
        //     its_,
        //     name_,
        //     symbol_,
        //     recoverableWindow_,
        //     governanceAddress_,
        //     baseERC20_,
        //     maxToClean
        // );
        // rwTEL = RWTEL(payable(address(new ERC1967Proxy{ salt: rwtelSalt }(address(rwTELImpl), ""))));
        // rwTEL.initialize(governanceAddress_, maxToClean, admin);

        // vm.stopBroadcast();

        // // asserts
        // assert(rwTEL.consensusRegistry() == deployments.ConsensusRegistry);
        // assert(address(rwTEL.interchainTokenService()) == deployments.its.InterchainTokenService);
        // assert(rwTEL.baseToken() == deployments.wTEL);
        // assert(rwTEL.governanceAddress() == admin);
        // assert(rwTEL.recoverableWindow() == recoverableWindow_);
        // assert(rwTEL.owner() == admin);
        // assert(keccak256(bytes(rwTEL.name())) == keccak256(bytes(name_)));
        // assert(keccak256(bytes(rwTEL.symbol())) == keccak256(bytes(symbol_)));

        // // todo:
        // // assert rwtelTokenManager == ethTELTokenManager

        // // logs
        // string memory root = vm.projectRoot();
        // string memory dest = string.concat(root, "/deployments/deployments.json");
        // vm.writeJson(LibString.toHexString(uint256(uint160(address(rwTELImpl))), 20), dest, ".rwTELImpl");
        // vm.writeJson(LibString.toHexString(uint256(uint160(address(rwTEL))), 20), dest, ".rwTEL");
        //     //todo: writeJson(deployments.everything
    }
}
