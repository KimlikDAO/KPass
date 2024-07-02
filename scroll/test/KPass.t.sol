// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {KPass} from "../KPass.sol";
import {Test} from "forge-std/Test.sol";
import {KPASS, KPASS_DEPLOYER, VOTING} from "interfaces/kimlikdao/addresses.sol";
import {amountAddr, amountAddrFrom} from "interfaces/types/amountAddr.sol";
import {uint128x2From} from "interfaces/types/uint128x2.sol";

contract KPassTest is Test {
    KPass private kpass;

    function setUp() public {
        vm.prank(KPASS_DEPLOYER);
        kpass = new KPass();
        assertEq(address(kpass), KPASS);
    }

    function test_DOMAIN_SEPARATOR() public view {
        assertEq(
            kpass.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes("KPASS")),
                    keccak256(bytes("1")),
                    0x82750,
                    KPASS
                )
            )
        );
    }

    function testTokenURI() public view {
        assertEq(
            kpass.tokenURI(0x3d5bad4604650569f28733f7ad6ec22835e775a0eb20bfd809d78ed2ae8abe47),
            "https://ipfs.kimlikdao.org/ipfs/QmSUAf9gusxTbZZn5nC7d44kHjfrDeu2gfSY31MRVET28n"
        );
        assertEq(
            kpass.tokenURI(0xd2abff978646ac494f499e9ecd6873414a0c6105196c8c2580d52769f3fc0523),
            "https://ipfs.kimlikdao.org/ipfs/QmcX2ScFVAVnEHrMk3xuf7HXfiGHzmMqdpAYb37zA5mbFp"
        );
        assertEq(
            kpass.tokenURI(uint256(keccak256("CID test 1"))),
            "https://ipfs.kimlikdao.org/ipfs/QmVh6DdiLVjUndMVBmdoG1hXKuWFiUdbUFqqPBkhtNxJhA"
        );
        assertEq(
            kpass.tokenURI(uint256(keccak256("CID test 2"))),
            "https://ipfs.kimlikdao.org/ipfs/QmcbtE4RC2KFStbyjCnjACgNSxZJSKww2XGFRAMFVG4sNu"
        );
        assertEq(
            kpass.tokenURI(uint256(keccak256("CID test 3"))),
            "https://ipfs.kimlikdao.org/ipfs/QmQY9mWApretyH5dVMuqPThn299xNRp1knzuF9yMuF9kmM"
        );
    }

    function testAuthenticationPriceFeeder() public {
        vm.expectRevert();
        kpass.updatePrice(amountAddrFrom(15, vm.addr(1)));

        vm.prank(VOTING);
        kpass.updatePrice(amountAddrFrom(15, vm.addr(1)));
        assertEq(kpass.priceIn(vm.addr(1)).lo(), 15);

        amountAddr[3] memory prices =
            [amountAddrFrom(17, address(1337)), amountAddr.wrap(0), amountAddr.wrap(0)];

        vm.expectRevert();
        kpass.updatePricesBulk(uint128x2From(1, 1), prices);

        vm.prank(VOTING);
        kpass.updatePricesBulk(uint128x2From(1, 1), prices);
        assertEq(kpass.priceIn(address(1337)).lo(), 17);
    }

    function testUpdatePrice() public {
        vm.prank(VOTING);
        kpass.updatePrice(amountAddrFrom(131, vm.addr(888)));
        assertEq(kpass.priceIn(vm.addr(888)).lo(), 131);
        assertEq(kpass.priceIn(vm.addr(888)).hi(), uint256(131 * 3) / 2);
    }

    function testUpdatePricesBulk() public {
        vm.prank(VOTING);
        kpass.updatePricesBulk(
            uint128x2From(7, 5),
            [
                amountAddrFrom(5, vm.addr(1)),
                amountAddrFrom(6, vm.addr(2)),
                amountAddrFrom(7, vm.addr(3))
            ]
        );

        assertEq(kpass.priceIn(vm.addr(1)).lo(), 5);
        assertEq(kpass.priceIn(vm.addr(1)).hi(), 7);
        assertEq(kpass.priceIn(vm.addr(2)).lo(), 6);
        assertEq(kpass.priceIn(vm.addr(2)).hi(), 8);
        assertEq(kpass.priceIn(vm.addr(3)).lo(), 7);
        assertEq(kpass.priceIn(vm.addr(3)).hi(), 9);
    }
}
