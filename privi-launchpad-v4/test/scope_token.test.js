const TokenFundingManager = artifacts.require('TokenFundingManager');
const ScopeToken = artifacts.require('ScopeToken');
const StakeToken = artifacts.require('StakeToken');
const Insurance = artifacts.require('Insurance');
const SPOracle = artifacts.require('SPOracle');
const AppTokenMock = artifacts.require('AppTokenMock');
const WithdrawManager = artifacts.require('WithdrawManager');

const { expectEvent, constants, time } = require('@openzeppelin/test-helpers');
const { getData, updateTimesOf } = require('../fabric');

const DISCOUNT_PRECISION = 1000;
const UNSTAKE_FEE = 50;

contract('ScopeToken', function (accounts) {
  let token_funding_manager;
  let app_token_mock;
  let scope_token;

  let tokenFundingData = getData('tokenFundingData', accounts);
  let priceOracleInfo = getData('priceOracleInfo', accounts);

  beforeEach(async () => {
    await updateTimesOf(tokenFundingData);

    // don't need to redeploy the implementations
    let scope_token_ = await ScopeToken.deployed();
    let stake_token_ = await StakeToken.deployed();
    let insurance_ = await Insurance.deployed();
    let oracle = await SPOracle.deployed();

    app_token_mock = await AppTokenMock.new();
    let withdraw_manager = await WithdrawManager.new();

    tokenFundingData.appToken = app_token_mock.address;

    token_funding_manager = await TokenFundingManager.new(
      withdraw_manager.address,
      scope_token_.address,
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

    // get the scope token address
    scope_token = await ScopeToken.at(log.args.scopeTokenAddress);
    insurance = await ScopeToken.at(log.args.insuranceAddress);
  });

  describe('scope tokens rewards', () => {
    it('can buy scope tokens by amount to get', async () => {
      let currentPrice = 1;

      let balanceAppToken1 = await app_token_mock.balanceOf(accounts[0]);

      await app_token_mock.approve(scope_token.address, 5 * currentPrice, { from: accounts[0] });
      await scope_token.buyTokensByAmountToGet(5, { from: accounts[0] });

      let balanceAppToken2 = await app_token_mock.balanceOf(accounts[0]);

      let balanceScopeToken = await scope_token.balanceOf(accounts[0]);

      assert.strictEqual(balanceScopeToken.toNumber(), 5, 'Invalid app balance');

      let difference = balanceAppToken1.sub(balanceAppToken2);
      let discount = Math.floor(
        (5 * currentPrice * tokenFundingData.fundingScopeRoundsData[0].discount) / DISCOUNT_PRECISION
      );

      assert.strictEqual(difference.toNumber(), 5 * currentPrice - discount, 'Invalid scope balance');
    });

    it('can buy scope tokens by amount to pay', async () => {
      let currentPrice = 1;

      let balanceAppToken1 = await app_token_mock.balanceOf(accounts[0]);

      await app_token_mock.approve(scope_token.address, 5 * currentPrice, { from: accounts[0] });
      await scope_token.buyTokensByAmountToPay(5 * currentPrice, { from: accounts[0] });

      let balanceAppToken2 = await app_token_mock.balanceOf(accounts[0]);

      let balanceScopeToken = await scope_token.balanceOf(accounts[0]);

      assert.strictEqual(balanceScopeToken.toNumber(), 5, 'Invalid app balance');

      let difference = balanceAppToken1.sub(balanceAppToken2);
      let discount = Math.floor(
        (5 * currentPrice * tokenFundingData.fundingScopeRoundsData[0].discount) / DISCOUNT_PRECISION
      );

      assert.strictEqual(difference.toNumber(), 5 * currentPrice - discount, 'Invalid scope balance');
    });

    it('can get balance and estimated payout', async () => {
      await app_token_mock.approve(scope_token.address, 5, { from: accounts[0] });
      await scope_token.buyTokensByAmountToGet(5, { from: accounts[0] });

      // reach unlock date (15 days in future)
      await time.increase(time.duration.days(15));

      // this value should be divided by PRECISION (1 million)
      let scopeTokenPayout = await scope_token.scopeTokenPayout();

      let balanceAndPayout = await scope_token.balanceAndPayoutOf(accounts[0]);
      assert.strictEqual(balanceAndPayout.balance.toNumber(), 5, 'Invalid balance');
      assert.strictEqual(balanceAndPayout.payout.toNumber(), scopeTokenPayout.toNumber(), 'Invalid payout');
    });
  });

  describe('scope tokens claiming', () => {
    it('can claim tokens at the right time', async () => {
      await app_token_mock.transfer(insurance.address, 1000, { from: accounts[0] });

      await app_token_mock.approve(scope_token.address, 100, { from: accounts[0] });
      await scope_token.buyTokensByAmountToGet(100, { from: accounts[0] });

      // reach unlock date (15 days in future)
      await time.increase(time.duration.days(15));

      let insuranceBalance = await app_token_mock.balanceOf(insurance.address);

      // right balance after disccount
      assert.strictEqual(insuranceBalance.toNumber(), 1095, 'Invalid insurance balance');

      await scope_token.claim({ from: accounts[0] });

      insuranceBalance = await app_token_mock.balanceOf(insurance.address);

      // right balance after claiming
      assert.strictEqual(insuranceBalance.toNumber(), 995, 'Invalid insurance balance');
    });
  });
});
