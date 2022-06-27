// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "contracts/TCKT.sol";
import "forge-std/Test.sol";

contract TCKTTest is Test {
    TCKT tckt = new TCKT();

    function testTokenURI0() public {
        assertEq(
            tckt.tokenURI(
                0x3d5bad4604650569f28733f7ad6ec22835e775a0eb20bfd809d78ed2ae8abe47
            ),
            "ipfs://QmSUAf9gusxTbZZn5nC7d44kHjfrDeu2gfSY31MRVET28n"
        );
        assertEq(
            tckt.tokenURI(
                0xd2abff978646ac494f499e9ecd6873414a0c6105196c8c2580d52769f3fc0523
            ),
            "ipfs://QmcX2ScFVAVnEHrMk3xuf7HXfiGHzmMqdpAYb37zA5mbFp"
        );
    }

    function testTokenURIGas() public view returns (string memory) {
        return
            tckt.tokenURI(
                0xd2abff978646ac494f499e9ecd6873414a0c6105196c8c2580d52769f3fc0523
            );
    }

    function testRevoke() public {
        assertEq(tckt.balanceOf(address(this)), 0);
        tckt.create(123123123);
        assertEq(tckt.balanceOf(address(this)), 1);
        tckt.revoke();
        assertEq(tckt.balanceOf(address(this)), 0);
    }

    function testSocialRevoke() public {
        uint256[] memory revokers = new uint256[](5);
        revokers[0] = uint256(1) << 160 | uint160(vm.addr(10));
        revokers[1] = uint256(1) << 160 | uint160(vm.addr(11));
        revokers[2] = uint256(1) << 160 | uint160(vm.addr(12));
        revokers[3] = uint256(1) << 160 | uint160(vm.addr(13));
        revokers[4] = uint256(1) << 160 | uint160(vm.addr(14));
        tckt.createWithRevokers(123123123, 4, revokers);

        assertEq(tckt.balanceOf(address(this)), 1);

        vm.prank(vm.addr(10));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 1);
        vm.prank(vm.addr(10));
        vm.expectRevert();
        tckt.revokeFriend(address(this));
        vm.prank(vm.addr(11));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 1);
        vm.prank(vm.addr(12));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 1);
        vm.prank(vm.addr(13));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 0);
    }
}
