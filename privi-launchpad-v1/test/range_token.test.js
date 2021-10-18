const AppFundingManager = artifacts.require('AppFundingManager');
const RangeToken = artifacts.require('RangeToken');
const SyntheticToken = artifacts.require('SyntheticToken');
const AppToken = artifacts.require('AppToken');
const FundingTokenMock = artifacts.require('FundingTokenMock');
const WithdrawManager = artifacts.require('WithdrawManager');

const { expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { getData, updateTimesOf } = require('../fabric');

const IPFS_HASH = 'QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB';
const PRECISION = 1000000;
const PRICE_PRECISION = 1000;

contract('RangeToken', function (accounts) {
  let app_funding_manager;
  let withdraw_manager;
  let range_token;
  let synthetic_token;
  let app_token;
  let funding_token;
  let range_token_proxy_address;
  let rt;

  let appData = getData('appData', accounts);

  beforeEach(async () => {
    await updateTimesOf(appData);

    // don't need to redeploy the implementations
    range_token = await RangeToken.deployed();
    synthetic_token = await SyntheticToken.deployed();
    app_token = await AppToken.deployed();
    withdraw_manager = await WithdrawManager.new();

    funding_token = await FundingTokenMock.new();

    appData.fundingToken = funding_token.address;

    app_funding_manager = await AppFundingManager.new(
      withdraw_manager.address,
      range_token.address,
      synthetic_token.address,
      app_token.address
    );

    await withdraw_manager.initialize(app_funding_manager.address);

    let tx = app_funding_manager.initializeAppFunding(appData, 'Test App Token', 'TAT', IPFS_HASH, {
      from: accounts[1],
    });
    let log = expectEvent(await tx, 'CreateApp', {});

    range_token_proxy_address = log.args.rangeTokenAddress;
    rt = await RangeToken.at(range_token_proxy_address);
  });

  describe('general functionalities', () => {
    it('has correct maturity date', async () => {
      let maturityDate = (await rt.maturityDate()).toNumber();

      // 15 seconds window for the miners
      assert.strictEqual(maturityDate, appData.t, 'Invalid maturity date');
    });

    it('has correct name and symbol', async () => {
      let name = await rt.name();
      let symbol = await rt.symbol();

      // 15 seconds window for the miners
      assert.strictEqual(name, 'Privi Range Token', 'Invalid name');
      assert.strictEqual(symbol, 'pRT', 'Invalid symbol');
    });

    it('has correct estimated payout', async () => {
      let estimation = await rt.currentEstimatedPayout();

      assert.isAtMost(estimation.toNumber(), (appData.s / appData.rMax) * PRECISION, 'Invalid estimated payout');
    });

    it('can get correct round number', async () => {
      let roundNumber = await rt.getRoundNumber();

      assert.strictEqual(roundNumber.toNumber(), 1, 'Invalid round number');
    });

    it('can get round token price', async () => {
      let roundPrice = await rt.getTokenPrice();

      assert.strictEqual(roundPrice.toNumber(), appData.fundingRangeRoundsData[0].tokenPrice, 'Invalid round price');
    });
  });

  describe('buying of tokens buy amount to get', () => {
    it("can't buy tokens by amount to get without allowance", async () => {
      await expectRevert(rt.buyTokensByAmountToGet(10), 'ERC20: transfer amount exceeds allowance');
    });

    it('can buy tokens by amount to get', async () => {
      let roundPrice = await rt.getTokenPrice();
      let amountToGet = 5;

      await funding_token.approve(rt.address, roundPrice * amountToGet, { from: accounts[0] });
      await rt.buyTokensByAmountToGet(amountToGet, { from: accounts[0] });

      let balance = await rt.balanceOf(accounts[0]);
      assert.strictEqual(balance.toNumber(), amountToGet, 'Invalid balance');
    });

    it("can't buy tokens by amount to get over the cap", async () => {
      let roundPrice = await rt.getTokenPrice();
      let amountToGet = appData.fundingRangeRoundsData[0].capTokenToBeSold / 2;

      await funding_token.approve(rt.address, roundPrice * amountToGet, { from: accounts[0] });
      await rt.buyTokensByAmountToGet(amountToGet, { from: accounts[0] });

      await funding_token.approve(rt.address, roundPrice * amountToGet, { from: accounts[0] });

      await expectRevert(rt.buyTokensByAmountToGet(amountToGet + 1, { from: accounts[0] }), 'Insuficient tokens');

      await funding_token.approve(rt.address, roundPrice * amountToGet, { from: accounts[0] });
      await rt.buyTokensByAmountToGet(amountToGet, { from: accounts[0] });

      await funding_token.approve(rt.address, roundPrice * amountToGet, { from: accounts[0] });
      await expectRevert(rt.buyTokensByAmountToGet(amountToGet, { from: accounts[0] }), 'All tokens sold');
    });
  });

  describe('buying of tokens buy amount to pay', () => {
    it("can't buy tokens by amount to pay without allowance", async () => {
      await expectRevert(rt.buyTokensByAmountToPay(10), 'ERC20: transfer amount exceeds allowance');
    });

    it('can buy tokens by amount to pay', async () => {
      let roundPrice = await rt.getTokenPrice();
      let amountToGet = 5;
      let amountToPay = (amountToGet * roundPrice) / PRICE_PRECISION;

      await funding_token.approve(rt.address, amountToPay, { from: accounts[0] });
      await rt.buyTokensByAmountToPay(amountToPay, { from: accounts[0] });

      let balance = await rt.balanceOf(accounts[0]);
      assert.strictEqual(balance.toNumber(), amountToGet, 'Invalid balance');
    });

    it("can't buy tokens by amount to pay over the cap", async () => {
      let roundPrice = await rt.getTokenPrice();
      let amountToGet = appData.fundingRangeRoundsData[0].capTokenToBeSold / 2;
      let amountToPay = (amountToGet * roundPrice) / PRICE_PRECISION;

      await funding_token.approve(rt.address, amountToPay, { from: accounts[0] });
      await rt.buyTokensByAmountToPay(amountToPay, { from: accounts[0] });

      await funding_token.approve(rt.address, amountToPay, { from: accounts[0] });

      await expectRevert(
        rt.buyTokensByAmountToPay(amountToPay + roundPrice, { from: accounts[0] }),
        'Insuficient tokens'
      );

      await funding_token.approve(rt.address, amountToPay, { from: accounts[0] });
      await rt.buyTokensByAmountToPay(amountToPay, { from: accounts[0] });

      await funding_token.approve(rt.address, amountToPay, { from: accounts[0] });
      await expectRevert(rt.buyTokensByAmountToPay(amountToPay, { from: accounts[0] }), 'All tokens sold');
    });
  });
});
