// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {IERC20Permit} from "interfaces/IERC20Permit.sol";
import {MockERC20Permit} from "interfaces/testing/MockTokens.sol";
import {OYLAMA, TCKO_DEPLOYER, TCKT_SIGNERS_DEPLOYER} from "interfaces/Addresses.sol";
import {TCKTSigners} from "contracts/TCKTSigners.sol";

contract TCKTSignersTest is Test {
    IERC20Permit private tcko;
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
        tcktSigners.approveSignerNode(vm.addr(2));

        vm.startPrank(vm.addr(2));
        tcko.approve(address(tcktSigners), tcktSigners.stakingDeposit());
        vm.stopPrank();

        vm.startPrank(TCKO_DEPLOYER);
        tcko.transfer(vm.addr(2), tcktSigners.stakingDeposit());
        vm.stopPrank();

        vm.prank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(2));

        vm.prank(OYLAMA);
        tcktSigners.slashSignerNode(vm.addr(2));
    }
}
