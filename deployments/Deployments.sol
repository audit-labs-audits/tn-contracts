// SPDX-License-Identifier UNLICENSED
pragma solidity 0.8.26;

/// @notice Foundry decodes JSON data to Solidity structs using lexicographical ordering
/// therefore upper-case struct member names must come **BEFORE** lower-case ones!
struct Deployments {
    address StablecoinImpl;
    address UniswapV2Factory;
    address UniswapV2Router02;
    address admin;
    address eAUD;
    address eCAD;
    address eCHF;
    address eEUR;
    address eGBP;
    address eHKD;
    address eJPY;
    address eMXN;
    address eNOK;
    address eSDR;
    address eSGD;
    address rwTEL;
    address wTEL;
    address wTEL_eAUD_Pool;
    address wTEL_eCAD_Pool;
    address wTEL_eCHF_Pool;
    address wTEL_eEUR_Pool;
    address wTEL_eGBP_Pool;
    address wTEL_eHKD_Pool;
    address wTEL_eJPY_Pool;
    address wTEL_eMXN_Pool;
    address wTEL_eNOK_Pool;
    address wTEL_eSDR_Pool;
    address wTEL_eSGD_Pool;
}