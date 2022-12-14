// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {MockERC20Permit} from "interfaces/testing/MockTokens.sol";
import {OYLAMA, TCKO_DEPLOYER, TCKT_SIGNERS_DEPLOYER} from "interfaces/Addresses.sol";
import {TCKTSigners} from "contracts/TCKTSigners.sol";

contract TCKTSignersTest is Test {
    MockERC20Permit private tcko;
    TCKTSigners private tcktSigners;

    function setUp() external {
        vm.prank(TCKO_DEPLOYER);
        tcko = new MockERC20Permit("TCKO", "TCKO", 6);

        vm.prank(TCKT_SIGNERS_DEPLOYER);
        tcktSigners = new TCKTSigners();
    }

    function testAuthorization() external {
        vm.expectRevert();
        tcktSigners.setStakingDeposit(1e12);
        vm.prank(OYLAMA);
        tcktSigners.setStakingDeposit(1e12);

        vm.expectRevert();
        tcktSigners.setSignersNeeded(5);
        vm.prank(OYLAMA);
        tcktSigners.setSignersNeeded(5);

        vm.expectRevert();
        tcktSigners.approveSignerNode(vm.addr(2));

        vm.startPrank(vm.addr(2));
        tcko.approve(address(tcktSigners), tcktSigners.stakingDeposit());
        tcko.mint(tcktSigners.stakingDeposit());
        vm.stopPrank();

        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(2));
    }

    function testStateTransition() external {
        vm.startPrank(vm.addr(1));
        tcko.mint(1e12);
        tcko.approve(address(tcktSigners), 1e12);
        vm.stopPrank();

        vm.startPrank(vm.addr(2));
        tcko.mint(1e12);
        tcko.approve(address(tcktSigners), 1e12);
        vm.stopPrank();

        vm.startPrank(vm.addr(1));
        vm.expectRevert();
        tcktSigners.unstake();
        vm.expectRevert();
        tcktSigners.withdraw();
        vm.stopPrank();

        vm.warp(10001);
        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(1));

        assertEq(tcktSigners.signerInfo(vm.addr(1)), (1e12 << 64) | 10001);

        vm.warp(10002);
        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(2));

        assertEq(tcktSigners.signerInfo(vm.addr(2)), (1e12 << 64) | 10002);

        vm.warp(10003);
        vm.prank(OYLAMA);
        tcktSigners.slashSignerNode(vm.addr(2));

        assertEq(
            tcktSigners.signerInfo(vm.addr(2)),
            (uint256(10003) << 128) | (1e12 << 64) | 10002
        );

        vm.warp(10004);
        vm.startPrank(vm.addr(1));

        vm.expectRevert();
        tcktSigners.withdraw();

        tcktSigners.unstake();

        vm.expectRevert();
        tcktSigners.unstake();

        vm.warp(10005 + 30 days);
        tcktSigners.withdraw();
        vm.stopPrank();

        assertEq(tcko.balanceOf(vm.addr(1)), 2e12);
    }

    function testSlashWhileUnstaking() external {
        vm.startPrank(vm.addr(1));
        tcko.mint(1e12);
        tcko.approve(address(tcktSigners), 1e12);
        vm.stopPrank();

        vm.startPrank(vm.addr(2));
        tcko.mint(1e12);
        tcko.approve(address(tcktSigners), 1e12);
        vm.stopPrank();

        vm.startPrank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(1));
        tcktSigners.approveSignerNode(vm.addr(2));
        vm.stopPrank();

        vm.warp(100);
        vm.prank(vm.addr(1));
        tcktSigners.unstake();
        vm.warp(200);
        vm.prank(OYLAMA);
    }
}
