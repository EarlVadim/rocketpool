import { RocketUser, RocketPool, RocketPoolMini, RocketSettings } from '../artifacts';


// Deposits ether with RocketPool
export async function scenarioDeposit({stakingTimeID, fromAddress, depositAmount, gas}) {
    const rocketUser = await RocketUser.deployed();
    const rocketPool = await RocketPool.deployed();
    const rocketSettings = await RocketSettings.deployed();

    // Get minimum ether required to launch minipool
    const minEtherRequired = await rocketSettings.getMiniPoolLaunchAmount.call();

    // Get initial minipools
    let openMiniPoolsOld = await rocketPool.getPoolsFilterWithStatus.call(0);
    let userMiniPoolsOld = await rocketPool.getPoolsFilterWithUserDeposit.call(fromAddress);

    // Get initial minipool properties
    let miniPoolBalanceOld = 0;
    let userCountOld = 0;
    let userBalanceOld = 0;
    if (openMiniPoolsOld.length) {
        let openMiniPoolOld = RocketPoolMini.at(openMiniPoolsOld[0]);
        miniPoolBalanceOld = web3.eth.getBalance(openMiniPoolOld.address);
        userCountOld = await openMiniPoolOld.getUserCount.call();
        if (userMiniPoolsOld.length) {
            let userMiniPoolOld = RocketPoolMini.at(userMiniPoolsOld[0]);
            let userRecordOld = await userMiniPoolOld.getUser.call(fromAddress);
            userBalanceOld = parseInt(userRecordOld[1].valueOf());
        }
    }

    // Deposit ether
    let result = await rocketUser.userDeposit(stakingTimeID, {
        from: fromAddress,
        to: rocketUser.address,
        value: depositAmount,
        gas: gas,
    });

    //// Get updated minipools
    //let openMiniPoolsNew = await rocketPool.getPoolsFilterWithStatus.call(0);
    //let userMiniPoolsNew = await rocketPool.getPoolsFilterWithUserDeposit.call(fromAddress);

    // Assert Transferred event was logged
    let log = result.logs.find(({ event }) => event == 'Transferred');
    assert.notEqual(log, undefined, 'Transferred event was not logged');

    // Get transfer properties
    let depositedAmount = log.args.value;
    let miniPoolAddress = log.args._to;

    // Get an instance of the minipool the deposit was sent to
    let miniPool = RocketPoolMini.at(miniPoolAddress);

    // Get minipool properties
    let miniPoolStatus = await miniPool.getStatus.call();
    let miniPoolBalance = web3.eth.getBalance(miniPool.address);

    // Get minipool user count and details
    let userCount = await miniPool.getUserCount.call();
    let userRecord = await miniPool.getUser.call(fromAddress);
    let userBalance = parseInt(userRecord[1].valueOf());

    // Check the deposited amount
    assert.equal(depositedAmount, depositAmount, 'Invalid deposited amount');

    // Check the minipool status
    let expectedStatus = (miniPoolBalance.valueOf() < minEtherRequired.valueOf() ? 0 : 1);
    assert.equal(miniPoolStatus.valueOf(), expectedStatus, 'Invalid minipool status');

    // No open minipools initially existed - expect new minipool to have been created
    if (!openMiniPoolsOld.length) {
        assert.equal(miniPoolBalance.valueOf(), depositAmount, 'Invalid minipool balance'); // Initial balance should be the deposit amount
        assert.equal(userCount.valueOf(), 1, 'Invalid user count'); // Initial user count should be 1
        assert.equal(userBalance, depositAmount, 'Invalid user balance'); // Initial user balance should be the deposit amount
    }

    // Open minipool initially existed - expect existing minipool to have been used
    else {
        assert.equal(miniPoolBalance.valueOf(), parseInt(miniPoolBalanceOld.valueOf()) + depositAmount, 'Invalid minipool balance'); // Balance should be increased by the deposit amount

        // No user minipools initially existed - expect user to have been added to minipool
        if (!userMiniPoolsOld.length) {
            assert.equal(userCount.valueOf(), parseInt(userCountOld.valueOf()) + 1, 'Invalid user count'); // User count should increment
            assert.equal(userBalance, depositAmount, 'Invalid user balance'); // Initial user balance should be the deposit amount
        }

        // User minipool initially existed - expect user's balance to have been updated
        else {
            assert.equal(userCount.valueOf(), userCountOld.valueOf(), 'Invalid user count'); // User count should remain the same
            assert.equal(userBalance, userBalanceOld + depositAmount, 'Invalid user balance'); // User balance should have updated
        }

    }

    // Return minipool instance
    return miniPool;

}


// Registers a backup withdrawal address and asserts withdrawal address was set correctly
export async function scenarioRegisterWithdrawalAddress({withdrawalAddress, miniPoolAddress, fromAddress, gas}) {
    const rocketUser = await RocketUser.deployed();

    // Register withdrawal address
    let result = await rocketUser.userSetWithdrawalDepositAddress(withdrawalAddress, miniPoolAddress, {
        from: fromAddress,
        gas: gas,
    });

    // Assert UserSetBackupWithdrawalAddress event was logged
    let log = result.logs.find(({ event }) => event == 'UserSetBackupWithdrawalAddress');
    assert.notEqual(log, undefined, 'UserSetBackupWithdrawalAddress event was not logged');

    // Assert withdrawal address was set correctly
    let newBackupAddress = log.args._userBackupAddress;
    assert.equal(newBackupAddress, withdrawalAddress, 'Withdrawal address does not match');

}


// Withdraws staking deposit
export async function scenarioWithdrawDeposit({miniPoolAddress, withdrawalAmount, fromAddress, gas}) {
    const rocketUser = await RocketUser.deployed();

    // Withdraw deposit
    await rocketUser.userWithdraw(miniPoolAddress, withdrawalAmount, {
        from: fromAddress,
        gas: gas,
    });

    // TODO: add assertions

}

