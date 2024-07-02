// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {KPassOwnerOf} from "../ethereum/KPassBase.sol";
import {uint128x2From} from "interfaces/types/uint128x2.sol";

contract KPass is KPassOwnerOf {
    constructor() {
        priceIn[address(0)] = uint128x2From(1.5e14, 1e14);
    }
}
