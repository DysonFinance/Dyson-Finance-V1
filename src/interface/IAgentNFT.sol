// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IAgentNFT {
    function agency() external view returns (address);
    function getApproved(uint tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    event Transfer(address indexed from, address indexed to, uint indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function supportsInterface(bytes4 interfaceID) external pure returns (bool);
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function tokenURI(uint tokenId) external view returns (string memory);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint balance);
    function ownerOf(uint tokenId) external view returns (address owner);
    function onMint(address user, uint tokenId) external;
    function safeTransferFrom(address from,address to,uint tokenId) external;
    function approve(address to, uint tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function transferFrom(address from,address to,uint tokenId) external;
    function safeTransferFrom(address from,address to,uint tokenId,bytes memory data) external;
}
