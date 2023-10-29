pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IDYSON {
    event TransferOwnership(address newOwner);
    event Transfer(address indexed from, address indexed to, uint amount);
    event Approval(address indexed owner, address indexed spender, uint amount);
    
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external view returns (bytes32);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function isMinter(address _minter) external view returns (bool);
    function nonces(address owner) external view returns (uint256);
    function owner() external view returns (address);
    function rescueERC20(address tokenAddress, address to, uint256 amount) external;
    function transferOwnership(address _owner) external;
    function addMinter(address _minter) external;
    function removeMinter(address _minter) external;
    function approve(address spender, uint amount) external returns (bool);
    function transfer(address to, uint amount) external returns (bool);
    function transferFrom(address from, address to, uint amount) external returns (bool);
    function mint(address to, uint amount) external returns (bool);
    function burn(address from, uint amount) external returns (bool);
    function permit(address _owner,address _spender,uint256 _amount,uint256 _deadline,uint8 _v,bytes32 _r,bytes32 _s) external;
}
