const AppFundingManager = artifacts.require('AppFundingManager');
const RangeToken = artifacts.require('RangeToken');
const SyntheticToken = artifacts.require('SyntheticToken');
const AppToken = artifacts.require('AppToken');
const FundingTokenMock = artifacts.require('FundingTokenMock');
const WithdrawManager = artifacts.require('WithdrawManager');

const { expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { getData, updateTimesOf } = require('../fabric');

const IPFS_HASH = 'QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB';
const PRICE_PRECISION = 1000;

contract('SyntheticToken', function (accounts) {
  let app_funding_manager;
  let withdraw_manager;
  let range_token;
  let synthetic_token;
  let app_token;
  let funding_token;
  let synthetic_token_proxy_address;
  let st;

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

    synthetic_token_proxy_address = log.args.syntheticTokenAddress;
    st = await SyntheticToken.at(synthetic_token_proxy_address);
  });

  describe('general functionalities', () => {
    it('has correct name and symbol', async () => {
      let name = await st.name();
      let symbol = await st.symbol();

      assert.strictEqual(name, 'Privi Synthetic Token', 'Invalid name');
      assert.strictEqual(symbol, 'pST', 'Invalid symbol');
    });

    it('can get correct round number', async () => {
      let roundNumber = await st.getRoundNumber();

      assert.strictEqual(roundNumber.toNumber(), 1, 'Invalid round number');
    });

    it('can get round token price', async () => {
      let roundPrice = await st.getTokenPrice();

      assert.strictEqual(
        roundPrice.toNumber(),
        appData.fundingSyntheticRoundsData[0].tokenPrice,
        'Invalid round price'
      );
    });
  });

  describe('buying of tokens buy amount to get', () => {
    it("can't buy tokens by amount to get without allowance", async () => {
      await expectRevert(st.buyTokensByAmountToGet(10), 'ERC20: transfer amount exceeds allowance');
    });

    it('can buy tokens by amount to get', async () => {
      let roundPrice = await st.getTokenPrice();
      let amountToGet = 5;

      await funding_token.approve(st.address, roundPrice * amountToGet, { from: accounts[0] });
      await st.buyTokensByAmountToGet(amountToGet, { from: accounts[0] });

      let balance = await st.balanceOf(accounts[0]);
      assert.strictEqual(balance.toNumber(), amountToGet, 'Invalid balance');
    });

    it("can't buy tokens by amount to get over the cap", async () => {
      let roundPrice = await st.getTokenPrice();
      let amountToGet = appData.fundingSyntheticRoundsData[0].capTokenToBeSold / 2;

      await funding_token.approve(st.address, roundPrice * amountToGet, { from: accounts[0] });
      await st.buyTokensByAmountToGet(amountToGet, { from: accounts[0] });

      await funding_token.approve(st.address, roundPrice * amountToGet, { from: accounts[0] });
      await expectRevert(st.buyTokensByAmountToGet(amountToGet + 1, { from: accounts[0] }), 'Insuficient tokens');

      await funding_token.approve(st.address, roundPrice * amountToGet, { from: accounts[0] });
      await st.buyTokensByAmountToGet(amountToGet, { from: accounts[0] });

      await funding_token.approve(st.address, roundPrice * amountToGet, { from: accounts[0] });
      await expectRevert(st.buyTokensByAmountToGet(amountToGet, { from: accounts[0] }), 'All tokens sold');
    });
  });

  describe('buying of tokens buy amount to pay', () => {
    it("can't buy tokens by amount to pay without allowance", async () => {
      await expectRevert(st.buyTokensByAmountToPay(10), 'ERC20: transfer amount exceeds allowance');
    });

    it('can buy tokens by amount to pay', async () => {
      let roundPrice = await st.getTokenPrice();
      let amountToGet = 5;
      let amountToPay = (amountToGet * roundPrice) / PRICE_PRECISION;

      await funding_token.approve(st.address, amountToPay, { from: accounts[0] });
      await st.buyTokensByAmountToPay(amountToPay, { from: accounts[0] });

      let balance = await st.balanceOf(accounts[0]);
      assert.strictEqual(balance.toNumber(), amountToGet, 'Invalid balance');
    });

    it("can't buy tokens by amount to pay over the cap", async () => {
      let roundPrice = await st.getTokenPrice();
      let amountToGet = appData.fundingSyntheticRoundsData[0].capTokenToBeSold / 2;
      let amountToPay = (amountToGet * roundPrice) / PRICE_PRECISION;

      await funding_token.approve(st.address, amountToPay, { from: accounts[0] });
      await st.buyTokensByAmountToPay(amountToPay, { from: accounts[0] });

      await funding_token.approve(st.address, amountToPay, { from: accounts[0] });

      await expectRevert(
        st.buyTokensByAmountToPay(amountToPay + roundPrice, { from: accounts[0] }),
        'Insuficient tokens'
      );

      await funding_token.approve(st.address, amountToPay, { from: accounts[0] });
      await st.buyTokensByAmountToPay(amountToPay, { from: accounts[0] });

      await funding_token.approve(st.address, amountToPay, { from: accounts[0] });
      await expectRevert(st.buyTokensByAmountToPay(amountToPay, { from: accounts[0] }), 'All tokens sold');
    });
  });
});
