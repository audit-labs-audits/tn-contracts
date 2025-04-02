// // SPDX-License-Identifier: MIT or Apache-2.0
// pragma solidity 0.8.26;

// import { Test, console2 } from "forge-std/Test.sol";
// import { Script } from "forge-std/Script.sol";
// import { IAxelarGateway } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
// import { AxelarAmplifierGateway } from
//     "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGateway.sol";
// import { AxelarAmplifierGatewayProxy } from
//     "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/AxelarAmplifierGatewayProxy.sol";
// import { BaseAmplifierGateway } from
//     "@axelar-network/axelar-gmp-sdk-solidity/contracts/gateway/BaseAmplifierGateway.sol";
// import { Message, CommandType } from
// "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/AmplifierGatewayTypes.sol";
// import {
//     WeightedSigner,
//     WeightedSigners,
//     Proof
// } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/types/WeightedMultisigTypes.sol";
// import { Create3Deployer } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/deploy/Create3Deployer.sol";
// import { AddressBytes } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/libs/AddressBytes.sol";
// import { Create3AddressFixed } from
// "@axelar-network/interchain-token-service/contracts/utils/Create3AddressFixed.sol";
// import { InterchainTokenService } from
// "@axelar-network/interchain-token-service/contracts/InterchainTokenService.sol";
// import { InterchainProxy } from "@axelar-network/interchain-token-service/contracts/proxies/InterchainProxy.sol";
// import { TokenManagerProxy } from "@axelar-network/interchain-token-service/contracts/proxies/TokenManagerProxy.sol";
// import { InterchainTokenDeployer } from
//     "@axelar-network/interchain-token-service/contracts/utils/InterchainTokenDeployer.sol";
// import { InterchainTokenFactory } from
// "@axelar-network/interchain-token-service/contracts/InterchainTokenFactory.sol";
// import { InterchainToken } from
//     "@axelar-network/interchain-token-service/contracts/interchain-token/InterchainToken.sol";
// import { TokenManagerDeployer } from
// "@axelar-network/interchain-token-service/contracts/utils/TokenManagerDeployer.sol";
// import { TokenManager } from "@axelar-network/interchain-token-service/contracts/token-manager/TokenManager.sol";
// import { ITokenManager } from "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManager.sol";
// import { ITokenManagerType } from
// "@axelar-network/interchain-token-service/contracts/interfaces/ITokenManagerType.sol";
// import { TokenHandler } from "@axelar-network/interchain-token-service/contracts/TokenHandler.sol";
// import { GatewayCaller } from "@axelar-network/interchain-token-service/contracts/utils/GatewayCaller.sol";
// import { AxelarGasService } from "@axelar-network/axelar-cgp-solidity/contracts/gas-service/AxelarGasService.sol";
// import { AxelarGasServiceProxy } from "../../../external/axelar-cgp-solidity/AxelarGasServiceProxy.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
// import { LibString } from "solady/utils/LibString.sol";
// import { ERC20 } from "solady/tokens/ERC20.sol";
// import { WTEL } from "../../../src/WTEL.sol";
// import { RWTEL } from "../../../src/RWTEL.sol";
// import { ExtCall } from "../../../src/interfaces/IRWTEL.sol";
// import { Create3Utils, Salts, ImplSalts } from "../../../deployments/utils/Create3Utils.sol";
// import { Deployments } from "../../../deployments/Deployments.sol";
// import { ITSUtils } from "../../../deployments/utils/ITSUtils.sol";

// /// @title Sepolia script to register canonical TEL and deploy its TokenManager using devnet configuration

// //todo: complete

// /// @dev Usage: `forge script script/testnet/deploy/DevnetCanonicalTELActions.s.sol \
// /// --rpc-url $SEPOLIA_RPC_URL -vvvv --private-key $ADMIN_PK`
// contract DevnetCanonicalTELActions is Script, ITSUtilsFork {
//     // TN contracts
//     WTEL wTEL; // already deployed
//     RWTEL rwTELImpl;
//     RWTEL rwTEL;
//     Create3Deployer create3;
//     AxelarAmplifierGateway gatewayImpl;
//     AxelarAmplifierGateway gateway;
//     TokenManagerDeployer tokenManagerDeployer;
//     InterchainToken interchainTokenImpl;
//     InterchainTokenDeployer itDeployer;
//     TokenManager tokenManagerImpl;
//     TokenHandler tokenHandler;
//     AxelarGasService gasServiceImpl;
//     AxelarGasService gasService;
//     GatewayCaller gatewayCaller;
//     InterchainTokenService itsImpl;
//     InterchainTokenService its; // InterchainProxy
//     InterchainTokenFactory itFactoryImpl;
//     InterchainTokenFactory itFactory; // InterchainProxy

//     // note that rwTEL interchainTokenSalt and interchainTokenId are the same as & derived from canonicalTEL
//     bytes32 canonicalInterchainSalt; // salt derived from canonicalTEL is used for new interchain TEL tokens
//     bytes32 canonicalInterchainTokenId; // tokenId derived from canonicalTEL is used for new interchain TEL
//         // TokenManagers
//     TokenManager canonicalTELTokenManager;

//     Deployments deployments;
//     address admin;
//     address rwtelOwner;

//     function setUp() public {
//         string memory root = vm.projectRoot();
//         string memory path = string.concat(root, "/deployments/deployments.json");
//         string memory json = vm.readFile(path);
//         bytes memory data = vm.parseJson(json);
//         deployments = abi.decode(data, (Deployments));

// _devnetConfig()
//     }

//     function run() public {
//         // vm.startBroadcast();

//         // vm.stopBroadcast();

//         // // asserts
//         // // assert canonicalInterchainSalt == itf.canonicalInterchainTokenDeploySalt();
//         // // assert canonicalInterchainTokenId == itf.canonicalInterchainTokenId();
//         // // assert rwtelTokenManager == ethTELTokenManager

//         // // logs
//         // string memory root = vm.projectRoot();
//         // string memory dest = string.concat(root, "/deployments/deployments.json");
//         // vm.writeJson(LibString.toHexString(uint256(uint160(address(canonicalTELTokenManager))), 20), dest,
// ".CanonicalTELTokenManager");
//         // vm.writeJson(LibString.toHexString(uint256(uint160(address(rwTELTokenManager))), 20), dest,
// ".RWTELTokenManager");
//         //     //todo: writeJson(deployments.everything
//     }
// }
