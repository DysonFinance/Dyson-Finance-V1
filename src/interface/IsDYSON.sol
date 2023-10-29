pragma solidity >=0.8.0;

// SPDX-License-Identifier: MIT

interface IsDYSON {
    event TransferOwnership(address newOwner);
    event Transfer(address indexed from, address indexed to, uint amount);
    event Approval(address indexed owner, address indexed spender, uint amount);
    event Stake(address indexed vaultOwner, address indexed depositor, uint amount, uint sDysonAmount, uint time);
    event Restake(address indexed vaultOwner, uint index, uint dysonAmountAdded, uint sDysonAmountAdded, uint time);
    event Unstake(address indexed vaultOwner, address indexed receiver, uint amount, uint sDysonAmount);
    event Migrate(address indexed vaultOwner, uint index);

    struct Vault {
        uint dysonAmount;
        uint sDysonAmount;
        uint unlockTime;
    }

    function initialRate() external view returns (uint);
    function initialTime() external view returns (uint);
    function stakingRate(uint lockDuration) external view returns (uint rate);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external view returns (bytes32);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function decimals() external view returns (uint8);
    function Dyson() external view returns (address);
    function owner() external view returns (address);
    function migration() external view returns (address);
    function totalSupply() external view returns (uint);
    function currentModel() external view returns (address);
    function balanceOf(address account) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function vaults(address vaultOwner, uint index) external view returns (uint dysonAmount, uint sDysonAmount, uint unlockTime);
    function vaultCount(address vaultOwner) external view returns (uint);
    function dysonAmountStaked(address account) external view returns (uint);
    function votingPower(address account) external view returns (uint);
    function nonces(address account) external view returns (uint);
    function transferOwnership(address _owner) external;
    function mint(address to, uint amount) external returns (bool);
    function burn(uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
    function transfer(address to, uint amount) external returns (bool);
    function transferFrom(address from, address to, uint amount) external returns (bool);
    function getStakingRate(uint lockDuration) external view returns (uint rate);
    function setStakingRateModel(address newModel) external;
    function setMigration(address _migration) external;
    function stake(address to, uint amount, uint lockDuration) external returns (uint sDysonAmount);
    function restake(uint index, uint amount, uint lockDuration) external returns (uint sDysonAmountAdded);
    function unstake(address to, uint index, uint sDysonAmount) external returns (uint amount);
    function migrate(uint index) external;
    function rescueERC20(address tokenAddress, address to, uint256 amount) external;
    function permit(address _owner, address _spender, uint256 _amount, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) external;
}
