// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "contracts/TCKT.sol";
import "forge-std/Test.sol";
import "interfaces/Addresses.sol";
import "interfaces/IERC20Permit.sol";
import "interfaces/MockTokens.sol";

contract TCKTTest is Test {
    TCKT private tckt;
    IERC20Permit private usdt;

    function setUpTokens() public {
        vm.setNonce(USDT_DEPLOYER, USDT_DEPLOY_N);
        vm.prank(USDT_DEPLOYER);
        usdt = new MockERC20Permit("USDt", "TetherToken", 6);
    }

    function setUp() public {
        vm.prank(TCKT_DEPLOYER);
        tckt = new TCKT();
    }

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
        revokers[0] = (uint256(1) << 160) | uint160(vm.addr(10));
        revokers[1] = (uint256(1) << 160) | uint160(vm.addr(11));
        revokers[2] = (uint256(1) << 160) | uint160(vm.addr(12));
        revokers[3] = (uint256(1) << 160) | uint160(vm.addr(13));
        revokers[4] = (uint256(1) << 160) | uint160(vm.addr(14));
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

    function testReduceRevokeThreshold() public {
        uint256[] memory revokers = new uint256[](5);
        revokers[0] = (uint256(1) << 160) | uint160(vm.addr(10));
        revokers[1] = (uint256(1) << 160) | uint160(vm.addr(11));
        revokers[2] = (uint256(1) << 160) | uint160(vm.addr(12));
        revokers[3] = (uint256(1) << 160) | uint160(vm.addr(13));
        revokers[4] = (uint256(1) << 160) | uint160(vm.addr(14));
        tckt.createWithRevokers(123123123, 1, revokers);

        assertEq(tckt.balanceOf(address(this)), 1);
        tckt.reduceRevokeThreshold(1);
        assertEq(tckt.balanceOf(address(this)), 1);
        vm.prank(vm.addr(10));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 0);
    }

    function testAddRevoker() public {
        uint256[] memory revokers = new uint256[](5);
        revokers[0] = (uint256(1) << 160) | uint160(vm.addr(10));
        tckt.createWithRevokers(123123123, 4, revokers);

        assertEq(tckt.balanceOf(address(this)), 1);
        tckt.addRevoker(vm.addr(11), 3);
        tckt.addRevoker(vm.addr(12), 1);

        vm.prank(vm.addr(11));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 1);

        vm.prank(vm.addr(12));
        tckt.revokeFriend(address(this));
        assertEq(tckt.balanceOf(address(this)), 0);
    }

    function testAuthenticationPriceFeeder() public {
        vm.expectRevert();
        tckt.updatePrice(vm.addr(1), 15);

        vm.prank(KIMLIKDAO_PRICE_FEEDER);
        tckt.updatePrice(vm.addr(1), 15);
        assertEq(tckt.priceIn(vm.addr(1)), 15);

        uint256[] memory prices = new uint256[](1);
        prices[0] = (17 << 160) | 1337;

        vm.expectRevert();
        tckt.updatePricesBulk(prices);

        vm.prank(KIMLIKDAO_PRICE_FEEDER);
        tckt.updatePricesBulk(prices);
        assertEq(tckt.priceIn(address(1337)), 17);
    }

    function testAuthenticationReportExposure() public {
        vm.expectRevert();
        tckt.reportExposure(bytes32(uint256(123123123)));

        vm.prank(THRESHOLD_2OF2_EXPOSURE_REPORTER);
        tckt.reportExposure(bytes32(uint256(123123123)));

        assertEq(
            tckt.exposureReported(bytes32(uint256(123123123))),
            block.timestamp
        );
    }

    function testNativeTokenPayment() public {
        vm.prank(KIMLIKDAO_PRICE_FEEDER);
        tckt.updatePrice(address(0), 0.05 ether);

        vm.expectRevert();
        tckt.create(123123123);

        vm.expectRevert();
        tckt.create{value: 0.04 ether}(123123123);

        vm.prank(KIMLIKDAO_PRICE_FEEDER);
        tckt.updatePrice(address(0), 0.04 ether);

        tckt.create{value: 0.04 ether}(1231231233);
        tckt.create{value: 0.05 ether}(123123123);

        vm.prank(KIMLIKDAO_PRICE_FEEDER);
        tckt.updatePrice(address(0), 0.05 ether);

        vm.expectRevert();
        tckt.create{value: 0.04 ether}(1231231233);
    }
}
