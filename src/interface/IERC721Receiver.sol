pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

/**
* @title ERC721 token receiver interface
* @dev Interface for any contract that wants to support safeTransfers
* from ERC721 asset contracts.
*/
interface IERC721Receiver {
    function onERC721Received(address, address, uint, bytes calldata) external returns (bytes4);
}