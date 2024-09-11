// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";
import { Script } from "forge-std/Script.sol";
import { LibString } from "solady/utils/LibString.sol";
import { AxelarAuthWeighted } from "@axelar-network/axelar-cgp-solidity/contracts/auth/AxelarAuthWeighted.sol";
import { TokenDeployer } from "@axelar-network/axelar-cgp-solidity/contracts/TokenDeployer.sol";
import { AxelarGateway } from "@axelar-network/axelar-cgp-solidity/contracts/AxelarGateway.sol";
import { AxelarGatewayProxy } from "@axelar-network/axelar-cgp-solidity/contracts/AxelarGatewayProxy.sol";
import { Deployments } from "../deployments/Deployments.sol";

/// @dev Usage: `forge script script/TestnetDeployTNBridgeContracts.s.sol --rpc-url $TN_RPC_URL -vvvv --private-key
/// $ADMIN_PK`
contract TestnetDeployTNBridgeContracts is Script {

    //todo use CREATE3 for reproducible addresses
    AxelarAuthWegihted authModule; // (sorted operator array == [admin])
    TokenDeployer tokenDeployer;
    AxelarGateway axelarGatewayImpl; // (authModule, tokenDeployer)
    AxelarGateway axelarGateway; // (gatewayImpl, params([operator], threshold, bytes('')))

    Deployments deployments;
    address admin; // operator

    bytes[] recentOperators;
    bytes gatewayParams;
    uint8 threshold;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/deployments.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        deployments = abi.decode(data, (Deployments));

        admin = deployments.admin;
        recentOperators.push(abi.encode(admin));
        address[] memory operators = new address[](1);
        operators[0] = admin;
        threshold = 1;
        gatewayParams = abi.encode(operators, threshold, '');
    }

    function run() public {
        vm.startBroadcast();

        // deploy auth module
        authModule = new AxelarAuthWeighted(recentOperators);
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
    }
}