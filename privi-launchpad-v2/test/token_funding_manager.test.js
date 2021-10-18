const TokenFundingManager = artifacts.require('TokenFundingManager');
const ScopeToken = artifacts.require('ScopeToken');
const StakeToken = artifacts.require('StakeToken');
const Insurance = artifacts.require('Insurance');
const SPOracle = artifacts.require('SPOracle');
const AppTokenMock = artifacts.require('AppTokenMock');
const WithdrawManager = artifacts.require('WithdrawManager');

const { expectEvent, expectRevert, constants } = require('@openzeppelin/test-helpers');
const { getData } = require('../fabric');

const UNSTAKE_FEE = 50;

contract('TokenFundingManager', function (accounts) {
  let token_funding_manager;
  let app_token_mock;

  let tokenFundingData = getData('tokenFundingData', accounts);
  let priceOracleInfo = getData('priceOracleInfo', accounts);

  beforeEach(async () => {
    // don't need to redeploy the implementations
    let scope_token = await ScopeToken.deployed();
    let stake_token = await StakeToken.deployed();
    let insurance = await Insurance.deployed();
    let oracle = await SPOracle.deployed();

    app_token_mock = await AppTokenMock.new();
    let withdraw_manager = await WithdrawManager.new();

    tokenFundingData.appToken = app_token_mock.address;

    token_funding_manager = await TokenFundingManager.new(
      withdraw_manager.address,
      scope_token.address,
      stake_token.address,
      insurance.address,
      oracle.address
    );
  });

  describe('initialize token funding', () => {
    it("can't initialize with invalid unlock date", async () => {
      let invalidData = { ...tokenFundingData, t: Math.floor(Date.now() / 1000) - 10 };
      await expectRevert(
        token_funding_manager.initializeTokenFunding(invalidData, priceOracleInfo, UNSTAKE_FEE, {
          from: accounts[1],
        }),
        'Invalid unlock date'
      );
    });

    it("can't initialize with invalid r interval", async () => {
      let invalidData = { ...tokenFundingData, rMin: tokenFundingData.rMax + 1 };
      await expectRevert(
        token_funding_manager.initializeTokenFunding(invalidData, priceOracleInfo, UNSTAKE_FEE, {
          from: accounts[1],
        }),
        'Invalid r interval'
      );
    });

    it('initialize app funding (emit event)', async () => {
      let tx = token_funding_manager.initializeTokenFunding(tokenFundingData, priceOracleInfo, UNSTAKE_FEE, {
        from: accounts[1],
      });
      expectEvent(await tx, 'CreateTokenFunding', {
        id: '1',
      });
    });

    it('can get token funding', async () => {
      await token_funding_manager.initializeTokenFunding(tokenFundingData, priceOracleInfo, UNSTAKE_FEE, {
        from: accounts[1],
      });

      // the app id is 1 (the first one)
      let tokenFunding = await token_funding_manager.getTokenFunding(1);

      assert.ok(tokenFunding.appTokenAddress, 'Invalid app token address');
      assert.ok(tokenFunding.insuranceAddress, 'Invalid insurance address');
      assert.ok(tokenFunding.stakeTokenAddress, 'Invalid stake token address');
      assert.ok(tokenFunding.scopeTokenAddress, 'Invalid scope token address');
    });
  });
});
