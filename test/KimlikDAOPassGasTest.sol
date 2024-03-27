// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "interfaces/Addresses.sol";
import "interfaces/IERC20Permit.sol";
import "interfaces/testing/MockTokens.sol";
import {KimlikDAOPass} from "contracts/KimlikDAOPass.sol";

contract KimlikDAOPassGasTest is Test {
    KimlikDAOPass private kpass;

    function setUp() public {
        vm.prank(KPASS_DEPLOYER);
        kpass = new KimlikDAOPass();
        assertEq(address(kpass), KPASS_ADDR);
    }

    function testTokenURI() public view {
        kpass.tokenURI(0xd2abff978646ac494f499e9ecd6873414a0c6105196c8c2580d52769f3fc0523);
    }

    function testCreate() external {
        kpass.create{value: 0.075 ether}(0xb90dbbe301d5d7d4189d8eb7e2eb45940cdd4d78828bb18a4c621775d840fb5e);
    }

    function testCreateWith3Revokers() public {
        kpass.createWithRevokers{value: 0.05 ether}(
            123123123,
            [
                (uint256(2) << 192) | (uint256(1) << 160) | uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                0,
                0
            ]
        );
    }

    function testCreateWith4Revokers() public {
        kpass.createWithRevokers{value: 0.05 ether}(
            123123123,
            [
                (uint256(2) << 192) | (uint256(1) << 160) | uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                (uint256(1) << 160) | uint160(vm.addr(13)),
                0
            ]
        );
    }

    function testCreateWith5Revokers() public {
        kpass.createWithRevokers{value: 0.05 ether}(
            123123123,
            [
                (uint256(2) << 192) | (uint256(1) << 160) | uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                (uint256(1) << 160) | uint160(vm.addr(13)),
                (uint256(1) << 160) | uint160(vm.addr(14))
            ]
        );
    }
}
