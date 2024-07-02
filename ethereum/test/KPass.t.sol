// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {KPass} from "../KPass.sol";
import {Test} from "forge-std/Test.sol";
import {KPASS} from "interfaces/kimlikdao/addresses.sol";

contract KPassEthereumTest is Test {
    function test_DOMAIN_SEPARATOR() public {
        KPass kpass = new KPass();
        assertEq(
            kpass.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes("KPASS")),
                    keccak256(bytes("1")),
                    0x1,
                    KPASS
                )
            )
        );
    }
}
