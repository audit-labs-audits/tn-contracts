// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { TokenDeployer } from "src/external/TokenDeployer.sol";
import { AxelarAuthWeighted } from "src/external/AxelarAuthWeighted.sol";
import { AxelarGateway } from "src/external/AxelarGateway.sol";
import { AxelarGatewayProxy } from "src/external/AxelarGatewayProxy.sol";
import { Deployments } from "../../deployments/Deployments.sol";

/// @dev Usage: `forge script script/deploy/TestnetDeployTNBridgeContracts.s.sol --rpc-url $TN_RPC_URL -vvvv --private-key
/// $ADMIN_PK`
contract TestnetDeployTNBridgeContracts is Script {

    //todo use CREATE3 for reproducible addresses
    AxelarAuthWeighted authModule; // (params == abi.encode([admin], [newWeight], newThreshold))
    TokenDeployer tokenDeployer;
    AxelarGateway axelarGatewayImpl; // (authModule, tokenDeployer)
    AxelarGateway axelarGateway; // (gatewayImpl, params([operator], threshold, bytes('')))

    Deployments deployments;
    address admin; // operator

    bytes[] authModuleParams;
    bytes gatewayParams;
    uint8 threshold;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        admin = deployments.admin;
        address[] memory operators = new address[](1);
        operators[0] = admin;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;
        threshold = 1;
        bytes memory operatorsWeightsThresholds = abi.encode(operators, weights, threshold);
        authModuleParams.push(operatorsWeightsThresholds);

        gatewayParams = abi.encode(operators, threshold, '');
    }

    function run() public {
        vm.startBroadcast();

        // deploy auth module
        authModule = new AxelarAuthWeighted(authModuleParams);
        // deploy token deployer
        tokenDeployer = new TokenDeployer();
        // deploy gateway impl 
        axelarGatewayImpl = new AxelarGateway(address(authModule), address(tokenDeployer));
        // deploy gateway proxy
        axelarGateway = AxelarGateway(address(new AxelarGatewayProxy(address(axelarGatewayImpl), gatewayParams))); 
        // transfer auth ownership to gatewayproxy
        authModule.transferOwnership(address(axelarGateway));


        // interchain service
        // deploy gasreceiver impl (owner == admin)
        // deploy gasreceiver proxy
        // initialize gasreceiver proxy (gasreceiver impl, owner bytes(''))
        // deploy tokenmanagerdeployer
        // ? deploy interchain token ([interchaintokenService])
        // deploy interchaintokendeployer ([interchaintoken?])
        // deploy tokenmanager ([interchaintokenservice])
        // deploy tokenhandler
        // get expected interchainTokenFactory addr 
        // deploy interchainTokenServiceContract impl ([
        //   tokenManagerDeployer, 
        //   interchainTokenDeployer, 
        //   gatewayProxy, 
        //   gasServiceProxy, 
        //   interchainTokenFactory, 
        //   name, 
        //   tokenManager, 
        //   tokenHandler
        // ])
        // deploy interchainTokenService (serviceImplementation, owner, params(owner, name, [''], ['']))
        // deploy tokenFactoryImpl (interchainTokenService)
        // deploy tokenFactory proxy(tokenFactoryImpl, owner, bytes(''))

        vm.stopBroadcast();

        // asserts

        // logs
        string memory root = vm.projectRoot();
        string memory dest = string.concat(root, "/deployments/deployments.json");
        vm.writeJson(
            LibString.toHexString(uint256(uint160(address(authModule))), 20),
            dest,
            ".AxelarAuthWeighted"
        );
        vm.writeJson(
            LibString.toHexString(uint256(uint160(address(tokenDeployer))), 20),
            dest,
            ".TokenDeployer"
        );
        vm.writeJson(
            LibString.toHexString(uint256(uint160(address(axelarGatewayImpl))), 20),
            dest,
            ".AxelarGatewayImpl"
        );
        vm.writeJson(
            LibString.toHexString(uint256(uint160(address(axelarGateway))), 20),
            dest,
            ".AxelarGatewayProxy"
        );
    }
}