const TokenFundingManager = artifacts.require('TokenFundingManager');
const ScopeToken = artifacts.require('ScopeToken');
const StakeToken = artifacts.require('StakeToken');
const Insurance = artifacts.require('Insurance');
const SPOracle = artifacts.require('SPOracle');
const AppTokenMock = artifacts.require('AppTokenMock');
const WithdrawManager = artifacts.require('WithdrawManager');

const { expectEvent, expectRevert, constants, time } = require('@openzeppelin/test-helpers');
const { getData, updateTimesOf } = require('../fabric');

const UNSTAKE_FEE = 50;

contract('StakeToken', function (accounts) {
  let token_funding_manager;
  let app_token_mock;
  let stake_token;
  let insurance;

  let tokenFundingData = getData('tokenFundingData', accounts);
  let priceOracleInfo = getData('priceOracleInfo', accounts);

  beforeEach(async () => {
    // update the dates before each test
    await updateTimesOf(tokenFundingData);

    // don't need to redeploy the implementations
    let scope_token = await ScopeToken.deployed();
    let stake_token_ = await StakeToken.deployed();
    let insurance_ = await Insurance.deployed();
    let oracle = await SPOracle.deployed();

    app_token_mock = await AppTokenMock.new();
    let withdraw_manager = await WithdrawManager.new();

    tokenFundingData.appToken = app_token_mock.address;

    token_funding_manager = await TokenFundingManager.new(
      withdraw_manager.address,
      scope_token.address,
      stake_token_.address,
      insurance_.address,
      oracle.address
    );

    let log = expectEvent(
      await token_funding_manager.initializeTokenFunding(tokenFundingData, priceOracleInfo, UNSTAKE_FEE, {
        from: accounts[1],
      }),
      'CreateTokenFunding',
      {}
    );

    // get the stake token address
    stake_token = await StakeToken.at(log.args.stakeTokenAddress);
    insurance = await StakeToken.at(log.args.insuranceAddress);
  });

  describe('stake tokens for rewards', () => {
    it("can't stake token without allowance", async () => {
      await expectRevert(stake_token.stake(100, { from: accounts[0] }), 'ERC20: transfer amount exceeds allowance');
    });

    it('can stake tokens (mint untransferable nft)', async () => {
      await app_token_mock.approve(stake_token.address, 100, { from: accounts[0] });
      expectEvent(await stake_token.stake(100, { from: accounts[0] }), 'StakeTokens', {
        holder: accounts[0],
        nftId: '1',
        quantity: '100',
      });
    });

    it('can stake tokens and get accrued reward', async () => {
      await app_token_mock.approve(stake_token.address, 100, { from: accounts[0] });
      expectEvent(await stake_token.stake(100, { from: accounts[0] }), 'StakeTokens', {
        holder: accounts[0],
        nftId: '1',
        quantity: '100',
      });

      // increment timestamp (10 days in future)
      await time.increase(time.duration.days(10));

      let accruedReward = await stake_token.getAccruedReward(1, { from: accounts[0] });
      assert.strictEqual(accruedReward.toNumber(), 3, 'Invalid accrued reward');
    });

    it('can unstake tokens', async () => {
      await app_token_mock.approve(stake_token.address, 100, { from: accounts[0] });
      expectEvent(await stake_token.stake(100, { from: accounts[0] }), 'StakeTokens', {
        holder: accounts[0],
        nftId: '1',
        quantity: '100',
      });

      expectEvent(await stake_token.unstake(1, { from: accounts[0] }), 'UnstakeTokens', {
        holder: accounts[0],
        quantityStaked: '100',
        quantityReceivedAfterFee: '95', // fee of 50 (5 percent)
      });
    });

    it('can get current reward', async () => {
      let currentReward = await stake_token.getCurrentReward();
      assert.strictEqual(currentReward.toNumber(), 50, 'Invalid reward');
    });

    it("can't transfer tokens", async () => {
      await app_token_mock.approve(stake_token.address, 100, { from: accounts[0] });
      await stake_token.stake(100, { from: accounts[0] });

      // the token id is 1 because is the first one created
      await expectRevert(
        stake_token.transferFrom(accounts[0], accounts[2], 1, { from: accounts[0] }),
        'Transfer not allowed'
      );
    });
  });

  describe('stake tokens claiming', () => {
    it("can't claim tokens without insurance balance", async () => {
      await app_token_mock.approve(stake_token.address, 100, { from: accounts[0] });

      await stake_token.stake(100, { from: accounts[0] });

      // reach unlock date (15 days in future)
      await time.increase(time.duration.days(15));

      await expectRevert(stake_token.claim(1, { from: accounts[0] }), 'ERC20: transfer amount exceeds balance');
    });

    it('can claim tokens at the right time', async () => {
      // transfer to insurance (this should be done by privi)
      app_token_mock.transfer(insurance.address, 1000, { from: accounts[0] });

      let inversion = 100;

      await app_token_mock.approve(stake_token.address, inversion, { from: accounts[0] });

      let balance1 = await app_token_mock.balanceOf(accounts[0]);

      await stake_token.stake(inversion, { from: accounts[0] });

      let balance2 = await app_token_mock.balanceOf(accounts[0]);

      // reach unlock date (15 days in future)
      await time.increase(time.duration.days(15));

      await stake_token.claim(1, { from: accounts[0] });

      let balance3 = await app_token_mock.balanceOf(accounts[0]);

      assert.strictEqual(balance2.sub(balance1).toNumber(), -inversion, 'Invalid inversion');
      assert.strictEqual(
        balance3.sub(balance2).toNumber(),
        inversion + (tokenFundingData.fundingStakeRoundsData[0].stakeReward / 1000) * inversion,
        'Invalid reward recovery'
      );
    });
  });
});
