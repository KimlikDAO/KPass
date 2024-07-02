// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {KPass} from "../KPass.sol";
import {KPassSigners} from "../KPassSigners.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20Permit} from "interfaces/erc/mock/ERC20Permit.sol";
import {
    KDAO as KDAO_ADDR,
    KDAO_DEPLOYER,
    KPASS,
    KPASS_DEPLOYER,
    KPASS_SIGNERS,
    KPASS_SIGNERS_DEPLOYER,
    VOTING
} from "interfaces/kimlikdao/addresses.sol";
import {KDAO} from "interfaces/kimlikdao/mock/KDAO.sol";
import {Signature, SignatureFrom} from "interfaces/types/Signature.sol";

contract KPassIntegrationTest is Test {
    KDAO private kdao;
    KPass private kpass;
    KPassSigners private kpassSigners;

    event ExposureReport(bytes32 indexed exposureReportID, uint256 timestamp);

    function setUp() public {
        vm.prank(KPASS_DEPLOYER);
        kpass = new KPass();
        vm.prank(KPASS_SIGNERS_DEPLOYER);
        kpassSigners = new KPassSigners();
        vm.prank(KDAO_DEPLOYER);
        kdao = new KDAO();

        assertEq(address(kpass), KPASS);
        assertEq(address(kpassSigners), KPASS_SIGNERS);
        assertEq(address(kdao), KDAO_ADDR);

        for (uint256 i = 1; i <= 10; ++i) {
            vm.startPrank(vm.addr(i));
            kdao.mint(200_000e6);
            kdao.approve(address(kpassSigners), 2e11);
            vm.stopPrank();
        }
    }

    function signOffExposureReport(bytes32 exposureReportID, uint256 timestamp, uint256 signerKey)
        internal
        pure
        returns (Signature memory sig)
    {
        bytes32 digest = keccak256(
            abi.encode(uint256(bytes32("\x19KimlikDAO hash\n")) | timestamp, exposureReportID)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return SignatureFrom(v, r, s);
    }

    function testReportFutureExposure() public {
        Signature[4] memory sigs = [
            signOffExposureReport(bytes32(uint256(123)), 100, 1),
            signOffExposureReport(bytes32(uint256(123)), 100, 2),
            signOffExposureReport(bytes32(uint256(123)), 100, 3),
            signOffExposureReport(bytes32(uint256(123)), 100, 4)
        ];
        vm.warp(99);
        vm.startPrank(VOTING);
        kpassSigners.approveSignerNode(vm.addr(1));
        kpassSigners.approveSignerNode(vm.addr(2));
        kpassSigners.approveSignerNode(vm.addr(3));
        kpassSigners.approveSignerNode(vm.addr(4));
        vm.stopPrank();
        kpassSigners.reportExposure(bytes32(uint256(123)), 100, [sigs[0], sigs[1], sigs[2]]);
    }

    function testReportExposure() public {
        vm.startPrank(VOTING);
        for (uint256 i = 1; i <= 10; ++i) {
            vm.warp(100 + 10 * i);
            kpassSigners.approveSignerNode(vm.addr(i));
        }
        vm.stopPrank();

        Signature[4] memory sigs = [
            signOffExposureReport(bytes32(uint256(123)), 130, 1),
            signOffExposureReport(bytes32(uint256(123)), 130, 2),
            signOffExposureReport(bytes32(uint256(123)), 130, 3),
            signOffExposureReport(bytes32(uint256(123)), 130, 4)
        ];
        vm.warp(140);
        vm.startPrank(VOTING);
        for (uint256 i = 1; i < 10; ++i) {
            kpassSigners.slashSignerNode(vm.addr(i));
        }
        vm.stopPrank();
        vm.expectRevert();
        kpassSigners.reportExposure(bytes32(uint256(123)), 130, [sigs[0], sigs[1], sigs[0]]);
        vm.expectRevert();
        kpassSigners.reportExposure(bytes32(uint256(123)), 130, [sigs[0], sigs[1], sigs[1]]);
        vm.expectRevert();
        kpassSigners.reportExposure(bytes32(uint256(123)), 130, [sigs[0], sigs[0], sigs[1]]);
        vm.expectEmit(true, true, true, true, address(kpassSigners));
        emit ExposureReport(bytes32(uint256(123)), uint256(130));
        kpassSigners.reportExposure(bytes32(uint256(123)), 130, [sigs[0], sigs[1], sigs[2]]);
    }

    function testReportBySlashedSigner() external {
        vm.warp(1000);
        vm.startPrank(VOTING);
        for (uint256 i = 1; i <= 10; ++i) {
            vm.warp(1000 + 10 * i);
            kpassSigners.approveSignerNode(vm.addr(i));
        }

        vm.warp(1110);
        for (uint256 i = 1; i < 10; ++i) {
            kpassSigners.slashSignerNode(vm.addr(i));
        }
        vm.stopPrank();

        Signature[4] memory sigs = [
            signOffExposureReport(bytes32(uint256(123)), 1111, 1),
            signOffExposureReport(bytes32(uint256(123)), 1111, 2),
            signOffExposureReport(bytes32(uint256(123)), 1111, 3),
            signOffExposureReport(bytes32(uint256(123)), 1111, 4)
        ];

        vm.expectRevert();
        kpassSigners.reportExposure(bytes32(uint256(123)), 1111, [sigs[0], sigs[1], sigs[2]]);
    }
}
