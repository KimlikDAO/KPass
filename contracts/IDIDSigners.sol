// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

uint256 constant END_TS_MASK = uint256(type(uint64).max) << 128;

uint256 constant DEPOSIT_MASK = uint256(type(uint64).max) << 64;

interface IDIDSigners {
    /**
     * Maps a signer node address to a bit packed struct.
     *
     *`signerInfo` layout:
     * |-- withdraw --|--  endTs --|-- deposit --|-- startTs --|
     * |--   64     --|--   64   --|--   64    --|--   64    --|
     *
     * The `withdraw` and `deposit` fields need 48 bits only. The struct has
     * 32 bits of additional space if need be.
     */
    function signerInfo(address signer) external view returns (uint256);
}
