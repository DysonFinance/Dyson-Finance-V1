// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "src/sDYSON.sol";
import "src/DYSON.sol";
import "./TestUtils.sol";

contract MigrationMock {
    function onMigrationReceived(address, uint, uint, uint) pure external returns (bytes4) {
        return 0xd4fb1792;
    }
}

contract sDYSONTest is TestUtils {
    address testOwner = address(this);
    uint constant STAKING_RATE_BASE_UNIT = 1e18;
    DYSON dyson = new DYSON(testOwner);
    sDYSON sDyson = new sDYSON(testOwner, address(dyson));
    StakingRateModel currentModel;

    // Handy accounts
    address alice = _nameToAddr("alice");
    address bob = _nameToAddr("bob");
    uint immutable INITIAL_WEALTH = 10**30;
    int unbackedSupplyCap = 100;

    function setUp() public {
        currentModel = new StakingRateModel(STAKING_RATE_BASE_UNIT / 16); // initialRate = 1
        sDyson.setStakingRateModel(address(currentModel));
        deal(address(dyson), alice, INITIAL_WEALTH);
        deal(address(dyson), bob, INITIAL_WEALTH);
        vm.prank(alice);
        dyson.approve(address(sDyson), INITIAL_WEALTH);
        vm.prank(bob);
        dyson.approve(address(sDyson), INITIAL_WEALTH);
        sDyson.setUnbackedSupplyCap(unbackedSupplyCap);
    }

    function testCannotTransferOwnershipByNonOwner() public {
        vm.prank(alice);
        vm.expectRevert("forbidden");
        sDyson.transferOwnership(alice);
    }

    function testTransferOwnership() public {
        sDyson.transferOwnership(alice);
        assertEq(sDyson.owner(), alice);
    }

    function testCannotSetStakingRateModelByNonOwner() public {
        StakingRateModel newStakingRateModel = new StakingRateModel(1e18 / 16);
        vm.prank(alice);
        vm.expectRevert("forbidden");
        sDyson.setStakingRateModel(address(newStakingRateModel));
    }

    function testSetStakingRateModel() public {
        StakingRateModel newStakingRateModel = new StakingRateModel(1e18 / 16);
        sDyson.setStakingRateModel(address(newStakingRateModel));
        assertEq(address(sDyson.currentModel()), address(newStakingRateModel));
    }

    function testCannotSetMigrationByNonOwner() public {
        vm.prank(alice);
        vm.expectRevert("forbidden");
        sDyson.setMigration(address(5566));
    }

    function testSetMigration() public {
        sDyson.setMigration(address(5566));
        assertEq(sDyson.migration(), address(5566));
    }

    function testCannotStakeForInvalidDuration() public {
        vm.prank(alice);
        uint amount = 1;
        uint tooShortDuration = 30 minutes - 1;
        uint tooLongDuration = 1461 days + 1;
        vm.expectRevert("invalid lockup");
        sDyson.stake(alice, amount, tooShortDuration);
        vm.expectRevert("invalid lockup");
        sDyson.stake(alice, amount, tooLongDuration);
    }

    function testMintUnbackedsDyson() public {
        uint ownerOldBalance = sDyson.balanceOf(testOwner);
        uint aliceOldBalance = sDyson.balanceOf(alice);
        uint mintAmount = 50;
        uint stakeAmount = 100;
        uint lockDuration = 30 days;
        uint sDysonAmountFromStake = currentModel.stakingRate(lockDuration) * stakeAmount / STAKING_RATE_BASE_UNIT;
        sDyson.mint(testOwner, mintAmount);

        sDyson.addMinter(alice);
        vm.startPrank(alice);
        sDyson.mint(alice, mintAmount);
        sDyson.stake(alice, stakeAmount, lockDuration);
        vm.stopPrank();

        uint ownerNewBalance = sDyson.balanceOf(testOwner);
        uint aliceNewBalance = sDyson.balanceOf(alice);
        assertEq(ownerNewBalance, ownerOldBalance + mintAmount);
        assertEq(aliceNewBalance, aliceOldBalance + sDysonAmountFromStake + mintAmount);
        // unbackedSupply only records minted / burned unbacked amount.
        assertEq(sDyson.unbackedSupply(), 100);
    }

    function testCannotMintWhenUserIsNotMinter() public {
        uint mintAmount = 100;

        vm.prank(alice);
        vm.expectRevert("forbidden");
        sDyson.mint(testOwner, mintAmount);
    }

    function testCannotMintWhenExceedUnbackedSupplyCap() public {
        uint mintAmount = 101;

        vm.expectRevert("exceed cap");
        sDyson.mint(testOwner, mintAmount);
    }

    function testBurnUnbackedsDyson() public {
        uint aliceOldBalance = sDyson.balanceOf(alice);
        uint stakeAmount = 1000;
        uint lockDuration = 30 days;
        uint burnAmount = 10;
        uint sDysonAmountFromStake = currentModel.stakingRate(lockDuration) * stakeAmount / STAKING_RATE_BASE_UNIT;

        vm.startPrank(alice);
        sDyson.stake(alice, stakeAmount, lockDuration);
        sDyson.burn(burnAmount);
        vm.stopPrank();

        uint aliceNewBalance = sDyson.balanceOf(alice);
        assertEq(aliceNewBalance, aliceOldBalance + sDysonAmountFromStake - burnAmount);
        // unbackedSupply only records minted / burned unbacked amount.
        assertEq(sDyson.unbackedSupply(), int(0) - int(burnAmount));
    }

    function testStake() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDysonAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount, lockDuration);
        assertEq(sDyson.balanceOf(alice), sDysonAmount);
        assertEq(sDyson.dysonAmountStaked(alice), amount);
        assertEq(sDyson.votingPower(alice), sDysonAmount);
    }

    function testStakeForOtherAccount() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDysonAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        sDyson.stake(bob, amount, lockDuration);
        assertEq(sDyson.balanceOf(bob), sDysonAmount);
        assertEq(sDyson.dysonAmountStaked(bob), amount);
        assertEq(sDyson.votingPower(bob), sDysonAmount);
    }

    function testStakeMultipleVaults() public {
        vm.startPrank(alice);
        uint lockDuration1 = 30 days;
        uint amount1 = 100;
        uint sDysonAmount1 = currentModel.stakingRate(lockDuration1) * amount1 / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount1, lockDuration1);

        uint lockDuration2 = 60 days;
        uint amount2 = 200;
        uint sDysonAmount2 = currentModel.stakingRate(lockDuration2) * amount2 / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount2, lockDuration2);
        assertEq(sDyson.balanceOf(alice), sDysonAmount1 + sDysonAmount2);
        assertEq(sDyson.dysonAmountStaked(alice), amount1 + amount2);
        assertEq(sDyson.votingPower(alice), sDysonAmount1 + sDysonAmount2);
    }

    function testCannotUnstakeBeforeUnlocked() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDysonAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount, lockDuration);
        skip(lockDuration - 1);
        vm.expectRevert("locked");
        sDyson.unstake(alice, 0, sDysonAmount);
    }

    function testCannotUnstakeMoreThanLockedAmount() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDysonAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount, lockDuration);
        skip(lockDuration);
        vm.expectRevert("exceed locked amount");
        sDyson.unstake(alice, 0, sDysonAmount + 1);
    }

    function testCannotUnstakeWithoutEnoughSDYSON() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDysonAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount, lockDuration);
        skip(lockDuration);

        // Alice transfer sDyson to Bob, so she has no sDyson.
        sDyson.transfer(bob, sDysonAmount);
        vm.expectRevert(stdError.arithmeticError);
        sDyson.unstake(alice, 0, sDysonAmount);
    }

    function testCannotUnstakeZeroAmount() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        sDyson.stake(alice, amount, lockDuration);
        skip(lockDuration);

        vm.expectRevert("invalid input amount");
        sDyson.unstake(alice, 0, 0);
    }

    function testUnstake() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        uint sDysonAmount = currentModel.stakingRate(lockDuration) * amount / STAKING_RATE_BASE_UNIT;
        sDyson.stake(alice, amount, lockDuration);
        skip(lockDuration);

        uint unstakesDysonAmount = 1;
        uint unstakeAmount = amount * unstakesDysonAmount / sDysonAmount;
        sDyson.unstake(alice, 0, unstakesDysonAmount);
        assertEq(sDyson.balanceOf(alice), sDysonAmount - unstakesDysonAmount);
        assertEq(sDyson.dysonAmountStaked(alice), amount - unstakeAmount);
        assertEq(sDyson.votingPower(alice), sDysonAmount - unstakesDysonAmount);
    }

    function testCannotRestakeBeforeStake() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        vm.expectRevert("invalid index");
        sDyson.restake(0, amount, lockDuration);
    }

    function testCannotRestakeNonExistedVault() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        sDyson.stake(alice, amount, lockDuration);

        uint nonExistedVaultId = 1;
        vm.expectRevert("invalid index");
        sDyson.restake(nonExistedVaultId, amount, lockDuration + 1);
    }

    function testCannotRestakeForInvalidDuration() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        sDyson.stake(alice, amount, lockDuration);
        skip(30 days);

        uint tooShortDuration = 30 minutes - 1;
        uint tooLongDuration = 1461 days + 1;
        vm.expectRevert("invalid lockup");
        sDyson.restake(0, amount, tooShortDuration);
        vm.expectRevert("invalid lockup");
        sDyson.restake(0, amount, tooLongDuration);
    }

    function testCannotRestakeForShorterLockDuration() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        sDyson.stake(alice, amount, lockDuration);

        vm.expectRevert("locked");
        sDyson.restake(0, amount, lockDuration - 1);

        skip(15 days);
        vm.expectRevert("locked");
        sDyson.restake(0, amount, lockDuration - 15 days - 1);
    }

    function testRestake() public {
        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        sDyson.stake(alice, amount, lockDuration);

        uint restakeLockDuration = 60 days;
        uint restakeAmount = 200;
        uint restakeSDysonAmount = currentModel.stakingRate(restakeLockDuration) * (amount + restakeAmount) / STAKING_RATE_BASE_UNIT;
        sDyson.restake(0, restakeAmount, restakeLockDuration);
        assertEq(sDyson.balanceOf(alice), restakeSDysonAmount);
        assertEq(sDyson.dysonAmountStaked(alice), amount + restakeAmount);
        assertEq(sDyson.votingPower(alice), restakeSDysonAmount);
    }

    function testCannotMigrateWithoutMigration() public {
        vm.startPrank(alice);
        vm.expectRevert("cannot migrate");
        sDyson.migrate(0);
    }

    function testCannotMigrateNonExistedVault() public {
        sDyson.setMigration(address(5566));
        vm.startPrank(alice);
        vm.expectRevert("invalid vault");
        sDyson.migrate(0);
    }

    function testMirgate() public {
        MigrationMock migration = new MigrationMock();
        sDyson.setMigration(address(migration));

        vm.startPrank(alice);
        uint lockDuration = 30 days;
        uint amount = 100;
        sDyson.stake(alice, amount, lockDuration);
        sDyson.migrate(0);
        assertEq(sDyson.dysonAmountStaked(alice), 0);
        assertEq(sDyson.votingPower(alice), 0);
    }
}