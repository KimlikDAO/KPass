// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

interface IERC721 {
    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function balanceOf(address) external view returns (uint256);

    function tokenURI(uint256 tokenId) external view returns (string memory);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
