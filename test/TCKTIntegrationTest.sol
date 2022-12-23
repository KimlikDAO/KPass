// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "interfaces/Addresses.sol";
import {MockERC20Permit} from "interfaces/testing/MockTokens.sol";
import {Signature, TCKT} from "contracts/TCKT.sol";
import {TCKTSigners} from "contracts/TCKTSigners.sol";

contract TCKTIntegrationTest is Test {
    MockERC20Permit private tcko;
    TCKT private tckt;
    TCKTSigners private tcktSigners;

    event ExposureReport(bytes32 indexed exposureReportID, uint256 timestamp);

    function setUp() public {
        vm.prank(TCKT_DEPLOYER);
        tckt = new TCKT();
        vm.prank(TCKT_SIGNERS_DEPLOYER);
        tcktSigners = new TCKTSigners();
        vm.prank(TCKO_DEPLOYER);
        tcko = new MockERC20Permit("KimlikDAO Tokeni", "TCKO", 6);

        assertEq(address(tckt), TCKT_ADDR);
        assertEq(address(tcktSigners), TCKT_SIGNERS);
        assertEq(address(tcko), TCKO_ADDR);

        for (uint256 i = 1; i <= 10; ++i) {
            vm.startPrank(vm.addr(i));
            tcko.mint(200_000e6);
            tcko.approve(address(tcktSigners), 2e11);
            vm.stopPrank();
        }
    }

    function signOffExposureReport(
        bytes32 exposureReportID,
        uint256 timestamp,
        uint256 signerKey
    ) internal pure returns (Signature memory sig) {
        bytes32 digest = keccak256(
            abi.encode(
                uint256(bytes32("\x19KimlikDAO digest")) | timestamp,
                exposureReportID
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        sig.r = r;
        sig.yParityAndS = ((uint256(v) - 27) << 255) | uint256(s);
    }

    function testReportFutureExposure() public {
        Signature[4] memory sigs = [
            signOffExposureReport(bytes32(uint256(123)), 100, 1),
            signOffExposureReport(bytes32(uint256(123)), 100, 2),
            signOffExposureReport(bytes32(uint256(123)), 100, 3),
            signOffExposureReport(bytes32(uint256(123)), 100, 4)
        ];
        vm.warp(1);
        vm.expectRevert();
        tckt.reportExposure(
            bytes32(uint256(123)),
            100,
            [sigs[0], sigs[1], sigs[2]]
        );
        vm.warp(99);
        vm.startPrank(OYLAMA);
        tcktSigners.approveSignerNode(vm.addr(1));
        tcktSigners.approveSignerNode(vm.addr(2));
        tcktSigners.approveSignerNode(vm.addr(3));
        tcktSigners.approveSignerNode(vm.addr(4));
        vm.stopPrank();
        tckt.reportExposure(
            bytes32(uint256(123)),
            100,
            [sigs[0], sigs[1], sigs[2]]
        );
    }

    function testReportExposure() public {
        vm.startPrank(OYLAMA);
        for (uint256 i = 1; i <= 10; ++i) {
            vm.warp(100 + 10 * i);
            tcktSigners.approveSignerNode(vm.addr(i));
        }
        vm.stopPrank();

        Signature[4] memory sigs = [
            signOffExposureReport(bytes32(uint256(123)), 130, 1),
            signOffExposureReport(bytes32(uint256(123)), 130, 2),
            signOffExposureReport(bytes32(uint256(123)), 130, 3),
            signOffExposureReport(bytes32(uint256(123)), 130, 4)
        ];
        vm.warp(140);
        vm.startPrank(OYLAMA);
        for (uint256 i = 1; i < 10; ++i) {
            tcktSigners.slashSignerNode(vm.addr(i));
        }
        vm.stopPrank();
        vm.expectRevert();
        tckt.reportExposure(
            bytes32(uint256(123)),
            130,
            [sigs[0], sigs[1], sigs[0]]
        );
        vm.expectRevert();
        tckt.reportExposure(
            bytes32(uint256(123)),
            130,
            [sigs[0], sigs[1], sigs[1]]
        );
        vm.expectRevert();
        tckt.reportExposure(
            bytes32(uint256(123)),
            130,
            [sigs[0], sigs[0], sigs[1]]
        );
        vm.expectEmit(true, true, true, true, address(tckt));
        emit ExposureReport(bytes32(uint256(123)), uint256(130));
        tckt.reportExposure(
            bytes32(uint256(123)),
            130,
            [sigs[0], sigs[1], sigs[2]]
        );
    }
}
