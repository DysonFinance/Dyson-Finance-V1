pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

import "interface/IPair.sol";
import "interface/IBribe.sol";
import "interface/IERC20.sol";
import "../lib/TransferHelper.sol";

/**
 * @title Contract to receive fee from DysonPair and distribute it to DAO wallet and Bribe
 */
contract FeeDistributor {
    using TransferHelper for address;
    address public owner;
    address public pair;
    address public bribe;
    address public pairToken0;
    address public pairToken1;
    address public daoWallet;
    uint public feeRateToDao; // stored in 1e18

    event FeeDistributed(uint token0ToDAO, uint token1ToDAO, uint token0ToBribe, uint token1ToBribe);

    constructor (address _owner, address _pair, address _bribe, address _daoWallet, uint _feeRateToDao) {
        owner = _owner;
        pair = _pair;
        bribe = _bribe;
        pairToken0 = IPair(_pair).token0();
        pairToken1 = IPair(_pair).token1();
        daoWallet = _daoWallet;
        feeRateToDao = _feeRateToDao;
    }

    function setFeeRateToDao(uint _feeRateToDao) external onlyOwner {
        feeRateToDao = _feeRateToDao;
    }

    function setDaoWallet(address _daoWallet) external onlyOwner {
        daoWallet = _daoWallet;
    }

    function setBribe(address _bribe) external onlyOwner {
        bribe = _bribe;
    }

    function setPair(address _pair) external onlyOwner {
        pair = _pair;
        pairToken0 = IPair(_pair).token0();
        pairToken1 = IPair(_pair).token1();
    }

    /**
     * @notice Distribute fee to DAO wallet and Bribe according to feeRateToDao
     */
    function distributeFee() external {
        uint nextWeek = block.timestamp / 1 weeks + 1;
        IPair(pair).collectFee();

        (uint fee0ToDAO, uint fee0ToBribe) = _calculateFee(pairToken0);
        pairToken0.safeTransfer(daoWallet, fee0ToDAO);
        IERC20(pairToken0).approve(bribe, fee0ToBribe);
        IBribe(bribe).addReward(pairToken0, nextWeek, fee0ToBribe);

        (uint fee1ToDao, uint fee1ToBribe) = _calculateFee(pairToken1);
        pairToken1.safeTransfer(daoWallet, fee1ToDao);
        IERC20(pairToken1).approve(bribe, fee1ToBribe);
        IBribe(bribe).addReward(pairToken1, nextWeek, fee1ToBribe);
        emit FeeDistributed(fee0ToDAO, fee1ToDao, fee0ToBribe, fee1ToBribe);
    }

    function _calculateFee(address _token) internal view returns (uint feeToDAO, uint feeToBribe) {
        uint fee = IERC20(_token).balanceOf(address(this));
        feeToDAO = fee * feeRateToDao / 1e18;
        feeToBribe = fee - feeToDAO;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "FORBIDDEN");
        _;
    }
}