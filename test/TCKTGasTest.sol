// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "contracts/TCKT.sol";
import "forge-std/Test.sol";
import "interfaces/Addresses.sol";
import "interfaces/IERC20Permit.sol";
import "interfaces/test/MockTokens.sol";

contract TCKTTest is Test {
    TCKT private tckt;

    function setUp() public {
        vm.prank(TCKT_DEPLOYER);
        tckt = new TCKT();
        assertEq(address(tckt), TCKT_ADDR);
    }

    function testTokenURI() public view {
        tckt.tokenURI(
            0xd2abff978646ac494f499e9ecd6873414a0c6105196c8c2580d52769f3fc0523
        );
    }

    function testCreateWithRevokers() public {
        tckt.createWithRevokers(
            123123123,
            [
                (uint256(2) << 192) |
                    (uint256(1) << 160) |
                    uint160(vm.addr(10)),
                (uint256(1) << 160) | uint160(vm.addr(11)),
                (uint256(1) << 160) | uint160(vm.addr(12)),
                0,
                0
            ]
        );
    }
}
