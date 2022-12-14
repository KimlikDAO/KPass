// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface StakedIERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external returns (uint256);

    event Transfer(address indexed from, address indexed to, uint256 amount);
}
