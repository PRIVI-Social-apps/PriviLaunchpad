const TokenFundingManager = artifacts.require('TokenFundingManager');
const ScopeToken = artifacts.require('ScopeToken');
const StakeToken = artifacts.require('StakeToken');
const AppTokenMock = artifacts.require('AppTokenMock');
const Insurance = artifacts.require('Insurance');
const SPOracle = artifacts.require('SPOracle');
const WithdrawManager = artifacts.require('WithdrawManager');

const { expectEvent, expectRevert, constants, time } = require('@openzeppelin/test-helpers');
const { getData, updateTimesOf } = require('../fabric');

const UNSTAKE_FEE = 50;
const REWARD_PRECISION = 1000;

contract('WithdrawManager', function (accounts) {
  let token_funding_manager;
  let withdraw_manager;
  let app_token_mock;
  let stake_token_proxy_address;
  let scope_token_proxy_address;
  let insurance_proxy_address;

  let tokenFundingData = getData('tokenFundingData', accounts);
  let priceOracleInfo = getData('priceOracleInfo', accounts);

  beforeEach(async () => {
    await updateTimesOf(tokenFundingData);

    // don't need to redeploy the implementations
    let scope_token = await ScopeToken.deployed();
    let stake_token = await StakeToken.deployed();
    let insurance = await Insurance.deployed();
    let oracle = await SPOracle.deployed();

    app_token_mock = await AppTokenMock.new();
    withdraw_manager = await WithdrawManager.new();

    tokenFundingData.appToken = app_token_mock.address;

    token_funding_manager = await TokenFundingManager.new(
      withdraw_manager.address,
      scope_token.address,
      stake_token.address,
      insurance.address,
      oracle.address
    );

    await withdraw_manager.initialize(token_funding_manager.address);

    let tx = token_funding_manager.initializeTokenFunding(tokenFundingData, priceOracleInfo, UNSTAKE_FEE, {
      from: accounts[1],
    });
    let log = expectEvent(await tx, 'CreateTokenFunding', {});

    stake_token_proxy_address = log.args.stakeTokenAddress;
    scope_token_proxy_address = log.args.scopeTokenAddress;
    insurance_proxy_address = log.args.insuranceAddress;
  });

  describe('withdraw funds (transfering)', () => {
    it('insurance contract starts with 0 balance', async () => {
      let insurance = await Insurance.at(insurance_proxy_address);

      let wBalance = await insurance.withdrawableBalance();
      assert.strictEqual(wBalance.toNumber(), 0, 'Invalid initial balance');
    });

    it('insurance has correct withdrawable balance after unlocking date', async () => {
      let stake_token = await StakeToken.at(stake_token_proxy_address);
      let insurance = await Insurance.at(insurance_proxy_address);

      // set the balance in 1000
      await app_token_mock.transfer(insurance.address, 1000, { from: accounts[0] });

      // stake 100 app tokens
      await app_token_mock.approve(stake_token.address, 100, { from: accounts[0] });
      await stake_token.stake(100, { from: accounts[0] });

      // reach unlock date (15 days in future)
      await time.increase(time.duration.days(15));

      let expectedBalance = 1000 - (100 * tokenFundingData.fundingStakeRoundsData[0].stakeReward) / REWARD_PRECISION;

      let wBalance = await insurance.withdrawableBalance();
      assert.strictEqual(wBalance.toNumber(), expectedBalance, 'Invalid withdrawable balance');
    });

    it("can't withdraw directly with more than one owner", async () => {
      let stake_token = await StakeToken.at(stake_token_proxy_address);
      let insurance = await Insurance.at(insurance_proxy_address);

      // set the balance in 1000
      await app_token_mock.transfer(insurance.address, 1000, { from: accounts[0] });

      // stake 100 app tokens
      await app_token_mock.approve(stake_token.address, 100, { from: accounts[0] });
      await stake_token.stake(100, { from: accounts[0] });

      // reach unlock date (15 days in future)
      await time.increase(time.duration.days(15));

      let wBalance = await insurance.withdrawableBalance();

      await expectRevert(
        withdraw_manager.withdrawTo(accounts[3], 1, wBalance, { from: accounts[2] }),
        'Multiple owners, voting is needed'
      );
    });

    it('can withdraw directly with only one owner', async () => {
      let tx = token_funding_manager.initializeTokenFunding(
        { ...tokenFundingData, owners: [accounts[2]] },
        priceOracleInfo,
        UNSTAKE_FEE,
        {
          from: accounts[1],
        }
      );
      let log = expectEvent(await tx, 'CreateTokenFunding', {});

      let stake_token_proxy_address = log.args.stakeTokenAddress;
      let insurance_proxy_address = log.args.insuranceAddress;

      let stake_token = await StakeToken.at(stake_token_proxy_address);
      let insurance = await Insurance.at(insurance_proxy_address);

      // set the balance in 1000
      await app_token_mock.transfer(insurance.address, 1000, { from: accounts[0] });

      // stake 100 app tokens
      await app_token_mock.approve(stake_token.address, 100, { from: accounts[0] });
      await stake_token.stake(100, { from: accounts[0] });

      // reach unlock date (15 days in future)
      await time.increase(time.duration.days(15));

      let wBalance = await insurance.withdrawableBalance();

      expectEvent(
        await withdraw_manager.withdrawTo(accounts[3], 2, wBalance, { from: accounts[2] }),
        'DirectWithdraw',
        { tokenFundingId: '2', recipient: accounts[3], amount: String(wBalance) }
      );

      let balance = await app_token_mock.balanceOf(accounts[3]);
      let withdrawableBalance = await insurance.withdrawableBalance();

      assert.strictEqual(balance.toNumber(), wBalance.toNumber(), 'Invalid recipient balance');
      assert.strictEqual(withdrawableBalance.toNumber(), 0, 'Invalid withdrawable balance');
    });

    it("can't propose withdrawal with only one owner", async () => {
      let tx = token_funding_manager.initializeTokenFunding(
        { ...tokenFundingData, owners: [accounts[2]] },
        priceOracleInfo,
        UNSTAKE_FEE,
        {
          from: accounts[1],
        }
      );
      let log = expectEvent(await tx, 'CreateTokenFunding', {});

      let stake_token_proxy_address = log.args.stakeTokenAddress;
      let insurance_proxy_address = log.args.insuranceAddress;

      let stake_token = await StakeToken.at(stake_token_proxy_address);
      let insurance = await Insurance.at(insurance_proxy_address);

      // set the balance in 1000
      await app_token_mock.transfer(insurance.address, 1000, { from: accounts[0] });

      // stake 100 app tokens
      await app_token_mock.approve(stake_token.address, 100, { from: accounts[0] });
      await stake_token.stake(100, { from: accounts[0] });

      // reach unlock date (15 days in future)
      await time.increase(time.duration.days(15));

      let wBalance = await insurance.withdrawableBalance();

      await expectRevert(
        withdraw_manager.createWithdrawProposal(accounts[3], 2, wBalance, { from: accounts[2] }),
        'Only one owner, voting is not needed'
      );
    });

    it('can propose withdrawal, vote and transfer', async () => {
      let stake_token = await StakeToken.at(stake_token_proxy_address);
      let insurance = await Insurance.at(insurance_proxy_address);

      // set the balance in 1000
      await app_token_mock.transfer(insurance.address, 1000, { from: accounts[0] });

      // stake 100 app tokens
      await app_token_mock.approve(stake_token.address, 100, { from: accounts[0] });
      await stake_token.stake(100, { from: accounts[0] });

      // reach unlock date (15 days in future)
      await time.increase(time.duration.days(15));

      let wBalance = await insurance.withdrawableBalance();

      expectEvent(
        await withdraw_manager.createWithdrawProposal(accounts[3], 1, wBalance, { from: accounts[2] }),
        'CreateWithdrawProposal',
        { tokenFundingId: '1', recipient: accounts[3], amount: String(wBalance), proposalId: '1' }
      );

      expectEvent(await withdraw_manager.voteWithdrawProposal(1, true, { from: accounts[2] }), 'VoteWithdrawProposal', {
        voter: accounts[2],
        tokenFundingId: '1',
        proposalId: '1',
      });

      expectEvent(await withdraw_manager.voteWithdrawProposal(1, true, { from: accounts[1] }), 'VoteWithdrawProposal', {
        voter: accounts[1],
        tokenFundingId: '1',
        proposalId: '1',
      });

      expectEvent(
        await withdraw_manager.voteWithdrawProposal(1, true, { from: accounts[0] }),
        'ApproveWithdrawProposal',
        {
          recipient: accounts[3],
          tokenFundingId: '1',
          amount: wBalance,
          proposalId: '1',
        }
      );

      let balance = await app_token_mock.balanceOf(accounts[3]);
      let withdrawableBalance = await insurance.withdrawableBalance();

      assert.strictEqual(balance.toNumber(), wBalance.toNumber(), 'Invalid recipient balance');
      assert.strictEqual(withdrawableBalance.toNumber(), 0, 'Invalid withdrawable balance');
    });

    it('can propose withdrawal, vote and deny', async () => {
      let stake_token = await StakeToken.at(stake_token_proxy_address);
      let insurance = await Insurance.at(insurance_proxy_address);

      // set the balance in 1000
      await app_token_mock.transfer(insurance.address, 1000, { from: accounts[0] });

      // stake 100 app tokens
      await app_token_mock.approve(stake_token.address, 100, { from: accounts[0] });
      await stake_token.stake(100, { from: accounts[0] });

      // reach unlock date (15 days in future)
      await time.increase(time.duration.days(15));

      let wBalance = await insurance.withdrawableBalance();

      expectEvent(
        await withdraw_manager.createWithdrawProposal(accounts[3], 1, wBalance, { from: accounts[2] }),
        'CreateWithdrawProposal',
        { tokenFundingId: '1', recipient: accounts[3], amount: String(wBalance), proposalId: '1' }
      );

      expectEvent(await withdraw_manager.voteWithdrawProposal(1, true, { from: accounts[2] }), 'VoteWithdrawProposal', {
        voter: accounts[2],
        tokenFundingId: '1',
        proposalId: '1',
      });

      expectEvent(
        await withdraw_manager.voteWithdrawProposal(1, false, { from: accounts[1] }),
        'DenyWithdrawProposal',
        {
          recipient: accounts[3],
          tokenFundingId: '1',
          amount: wBalance,
          proposalId: '1',
        }
      );

      await expectRevert(withdraw_manager.voteWithdrawProposal(1, true, { from: accounts[0] }), 'Unexistent proposal');
    });
  });
});
