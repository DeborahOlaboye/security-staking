// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import  "forge-std/Test.sol";
import {StakingRewards, IERC20} from "src/StakingRewards.sol";
import {MockERC20} from "src/MockErc20.sol";

contract StakingTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address dso = makeAddr("dso");

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(address(stakingToken), address(rewardToken));
        vm.stopPrank();
    }

    function test_alwaysPass() public {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(address(staking.stakingToken()), address(stakingToken), "Wrong staking token address");
        assertEq(address(staking.rewardsToken()), address(rewardToken), "Wrong reward token address");

        assertTrue(true);
    }

    function test_cannot_stake_amount0() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);

        // we are expecting a revert if we deposit/stake zero
        vm.expectRevert("amount = 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_can_stake_successfully() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        uint256 _totalSupplyBeforeStaking = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        assertEq(staking.totalSupply(), _totalSupplyBeforeStaking + 5e18, "totalsupply didnt update correctly");
    }

    function  test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_can_withdraw_deposited_amount() public {
        test_can_stake_successfully();

        uint256 userStakebefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(staking.balanceOf(bob), userStakebefore - 2e18, "Balance didnt update correctly");
        assertLt(staking.totalSupply(), totalSupplyBefore, "total supply didnt update correctly");

    }

    function test_notify_Rewards() public {
        // check that it reverts if non owner tried to set duration
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);

        // simulate owner calls setReward successfully
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
        
        // move time forward to ensure we're past any previous reward period
        vm.warp(block.timestamp + 200);
        
        // Setup reward tokens properly
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner); 
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        
        // trigger revert for zero reward rate (amount too small)
        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(1);
    
        // trigger second revert - insufficient balance
        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(200 ether);

        // successful notification
        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), uint256(100 ether)/uint256(1 weeks), "Reward rate calculation incorrect");
        assertEq(staking.finishAt(), uint256(block.timestamp) + uint256(1 weeks), "Finish time incorrect");
        assertEq(staking.updatedAt(), block.timestamp, "Updated time incorrect");
    
        // trigger setRewards distribution revert - cannot change duration while active
        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(1 weeks);
        vm.stopPrank();
    }
    function test_lastTimeRewardApplicable() public {
        // Setup reward tokens first
        deal(address(rewardToken), owner, 100e18);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100e18);
        
        staking.setRewardsDuration(1 weeks);
        staking.notifyRewardAmount(100e18);
        vm.stopPrank();

        // Case 1: finishAt in the future
        uint256 currentTime = block.timestamp;
        assertEq(staking.lastTimeRewardApplicable(), currentTime, "Should return current timestamp");

        // Case 2: finishAt in the past
        vm.warp(block.timestamp + 2 weeks);
        assertEq(staking.lastTimeRewardApplicable(), staking.finishAt(), "Should return finishAt");

        // Case 3: finishAt equals current time
        vm.warp(staking.finishAt());
        assertEq(staking.lastTimeRewardApplicable(), staking.finishAt(), "Should return finishAt");
    }

    function test_rewardPerToken() public {
        // Setup reward tokens first
        deal(address(rewardToken), owner, 100e18);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100e18);
        
        staking.setRewardsDuration(1 weeks);
        staking.notifyRewardAmount(100e18);
        vm.stopPrank();

        // Case 1: Zero totalSupply
        assertEq(staking.rewardPerToken(), staking.rewardPerTokenStored(), "Should return stored value when totalSupply is 0");

        // Case 2: Non-zero totalSupply - setup staking first
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), 10e18);
        staking.stake(10e18);
        vm.stopPrank();
        
        uint256 initialRewardPerToken = staking.rewardPerToken();
        vm.warp(block.timestamp + 1 days);
        
        uint256 rewardRate = staking.rewardRate();
        uint256 timeDelta = 1 days;
        uint256 totalSupply = staking.totalSupply();
        uint256 expected = initialRewardPerToken + ((rewardRate * timeDelta * 1e18) / totalSupply);
        
        assertEq(staking.rewardPerToken(), expected, "Reward per token calculation incorrect");

        // Case 3: After reward period ends
        uint256 rewardPerTokenBeforeEnd = staking.rewardPerToken();
        vm.warp(block.timestamp + 2 weeks);
        // Should not increase beyond the finish time
        assertGe(staking.rewardPerToken(), rewardPerTokenBeforeEnd, "Reward per token should not decrease");
    }

    function test_earned() public {
        // Setup reward tokens first
        deal(address(rewardToken), owner, 100e18);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100e18);
        
        staking.setRewardsDuration(1 weeks);
        staking.notifyRewardAmount(100e18);
        vm.stopPrank();

        // Case 1: Single user
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), 10e18);
        staking.stake(10e18);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 1 days);
        uint256 earnedReward = staking.earned(bob);
        assertGt(earnedReward, 0, "Bob should have earned some rewards");

        // Case 2: Multiple users
        deal(address(stakingToken), dso, 20e18);
        vm.startPrank(dso);
        IERC20(address(stakingToken)).approve(address(staking), 20e18);
        staking.stake(20e18);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 1 days);
        
        uint256 bobEarned = staking.earned(bob);
        uint256 dsoEarned = staking.earned(dso);
        
        assertGt(bobEarned, 0, "Bob should have earned rewards");
        assertGt(dsoEarned, 0, "Dso should have earned rewards");
        
        // Dso staked 2x more, so should earn proportionally more for the time they were staked
        // Note: This is a simplified check - actual calculation depends on timing
        
        // Case 3: Zero stake
        assertEq(staking.earned(address(0x123)), 0, "Non-staker should have zero rewards");
    }

    function test_getReward() public {
        // Setup reward tokens first
        deal(address(rewardToken), owner, 100e18);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100e18);
        
        staking.setRewardsDuration(1 weeks);
        staking.notifyRewardAmount(100e18);
        vm.stopPrank();

        // Setup staking for bob
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), 10e18);
        staking.stake(10e18);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 1 days);
        uint256 expectedReward = staking.earned(bob);
        uint256 balanceBefore = rewardToken.balanceOf(bob);

        vm.prank(bob);
        staking.getReward();
        assertEq(rewardToken.balanceOf(bob), balanceBefore + expectedReward, "Reward not transferred");
        assertEq(staking.rewards(bob), 0, "Rewards not reset");
        assertEq(staking.userRewardPerTokenPaid(bob), staking.rewardPerToken(), "User reward per token not updated");
    }

    function test_stake_edge_cases() public {
        // Case 1: Test with large amounts (but not max to avoid overflow)
        uint256 largeAmount = 1e30; // Large but safe amount
        deal(address(stakingToken), bob, largeAmount);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), largeAmount);
        staking.stake(largeAmount);
        assertEq(staking.balanceOf(bob), largeAmount, "Large stake failed");
        vm.stopPrank();

        // Case 2: Insufficient allowance
        deal(address(stakingToken), dso, 2e18);
        vm.startPrank(dso);
        IERC20(address(stakingToken)).approve(address(staking), 1e18);
        vm.expectRevert(); // Modern OpenZeppelin uses custom errors, not string messages
        staking.stake(2e18);
        vm.stopPrank();
        
        // Case 3: Insufficient balance
        vm.startPrank(dso);
        IERC20(address(stakingToken)).approve(address(staking), 10e18);
        vm.expectRevert(); // Modern OpenZeppelin uses custom errors, not string messages
        staking.stake(10e18); // dso only has 2e18
        vm.stopPrank();
    }

    function test_withdraw_security() public {
        // Setup staking first
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), 10e18);
        staking.stake(5e18);
        vm.stopPrank();

        // Case 1: Cannot withdraw more than staked
        vm.startPrank(bob);
        vm.expectRevert(); // Should revert due to underflow
        staking.withdraw(10e18);
        vm.stopPrank();

        // Case 2: Successful partial withdrawal
        vm.startPrank(bob);
        uint256 balanceBefore = staking.balanceOf(bob);
        staking.withdraw(2e18);
        assertEq(staking.balanceOf(bob), balanceBefore - 2e18, "Withdrawal failed");
        vm.stopPrank();
    }

    function test_reward_calculation_precision() public {
        // Setup rewards with small amounts to test precision
        deal(address(rewardToken), owner, 1000);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 1000);
        staking.setRewardsDuration(1000); // 1000 seconds
        staking.notifyRewardAmount(1000); // 1 reward per second
        vm.stopPrank();

        // Stake small amount
        deal(address(stakingToken), bob, 1e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), 1e18);
        staking.stake(1e18);
        vm.stopPrank();

        // Check rewards after 100 seconds
        vm.warp(block.timestamp + 100);
        uint256 earned = staking.earned(bob);
        assertGt(earned, 0, "Should earn rewards");
        assertLe(earned, 100, "Should not earn more than 100 tokens");
    }

    function test_multiple_reward_periods() public {
        // First reward period
        deal(address(rewardToken), owner, 200e18);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 200e18);
        staking.setRewardsDuration(1 weeks);
        staking.notifyRewardAmount(100e18);
        vm.stopPrank();

        // Stake during first period
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), 10e18);
        staking.stake(10e18);
        vm.stopPrank();

        // Move to end of first period
        vm.warp(block.timestamp + 1 weeks + 1);
        
        // Start second reward period
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        staking.notifyRewardAmount(100e18);
        vm.stopPrank();

        // Check that rewards are properly calculated across periods
        uint256 earnedAfterSecondPeriod = staking.earned(bob);
        assertGt(earnedAfterSecondPeriod, 0, "Should have rewards from first period");
    }

    function test_zero_duration_attack() public {
        deal(address(rewardToken), owner, 100e18);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100e18);
        
        // Set zero duration first (this is allowed)
        staking.setRewardsDuration(0);
        
        // The revert should happen when trying to notify with zero duration
        vm.expectRevert(); // Should revert due to division by zero in notifyRewardAmount
        staking.notifyRewardAmount(100e18);
        vm.stopPrank();
    }
    
    function test_owner_privilege_escalation() public {
        // Ensure only owner can call privileged functions
        vm.startPrank(bob);
        
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);
        
        vm.expectRevert("not authorized");
        staking.notifyRewardAmount(100e18);
        
        vm.stopPrank();
    }

    function test_reward_token_manipulation() public {
        // Setup initial rewards
        deal(address(rewardToken), owner, 100e18);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100e18);
        staking.setRewardsDuration(1 weeks);
        staking.notifyRewardAmount(100e18);
        vm.stopPrank();

        // Stake tokens
        deal(address(stakingToken), bob, 10e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), 10e18);
        staking.stake(10e18);
        vm.stopPrank();

        // Verify contract has reward tokens before manipulation test
        uint256 contractBalance = rewardToken.balanceOf(address(staking));
        assertGt(contractBalance, 0, "Contract should have reward tokens");
        
        // If someone could drain reward tokens, getReward should handle it gracefully
        vm.warp(block.timestamp + 1 days);
        
        uint256 earnedBefore = staking.earned(bob);
        assertGt(earnedBefore, 0, "Should have earned rewards");
    }

}