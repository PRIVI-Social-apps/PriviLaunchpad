const AppFundingManager = artifacts.require('AppFundingManager');
const RangeToken = artifacts.require('RangeToken');
const SyntheticToken = artifacts.require('SyntheticToken');
const AppToken = artifacts.require('AppToken');
const FundingTokenMock = artifacts.require('FundingTokenMock');
const WithdrawManager = artifacts.require('WithdrawManager');

const { expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');
const { getData, updateTimesOf } = require('../fabric');

const IPFS_HASH = 'QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB';
const PRECISION = 1000000;

contract('AppToken', function (accounts) {
  let app_funding_manager;
  let withdraw_manager;
  let range_token;
  let synthetic_token;
  let app_token;
  let funding_token;
  let synthetic_token_proxy_address;
  let range_token_proxy_address;
  let app_token_proxy_address;

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
    range_token_proxy_address = log.args.rangeTokenAddress;
    app_token_proxy_address = log.args.appTokenAddress;
  });

  it('has correct name and symbol', async () => {
    let at = await AppToken.at(app_token_proxy_address);
    let name = await at.name();
    let symbol = await at.symbol();

    assert.strictEqual(name, 'Test App Token', 'Invalid name');
    assert.strictEqual(symbol, 'TAT', 'Invalid symbol');
  });

  it("can't claim before launching date", async () => {
    let at = await AppToken.at(app_token_proxy_address);
    await expectRevert(at.claim(), 'Launching date not reached yet');
  });

  it('can successfully claim synthetic and range tokens', async () => {
    let tx = app_funding_manager.initializeAppFunding(appData, 'Test App Token', 'TAT', IPFS_HASH, {
      from: accounts[1],
    });
    let log = expectEvent(await tx, 'CreateApp', {});

    let synthetic_token_proxy_address2 = log.args.syntheticTokenAddress;
    let range_token_proxy_address2 = log.args.rangeTokenAddress;
    let app_token_proxy_address2 = log.args.appTokenAddress;

    // get synthetic tokens
    let st = await SyntheticToken.at(synthetic_token_proxy_address2);
    let roundPriceS = await st.getTokenPrice();
    let amountToGetS = 7;

    await funding_token.approve(st.address, roundPriceS * amountToGetS, { from: accounts[0] });
    await st.buyTokensByAmountToGet(amountToGetS, { from: accounts[0] });

    // get range tokens
    let rt = await RangeToken.at(range_token_proxy_address2);
    let roundPriceR = await rt.getTokenPrice();
    let amountToGetR = 5;

    await funding_token.approve(rt.address, roundPriceR * amountToGetR, { from: accounts[0] });
    await rt.buyTokensByAmountToGet(amountToGetR, { from: accounts[0] });

    // reach unlock date (15 days in future)
    await time.increase(time.duration.days(15));

    // try to claim (all calls where made from accounts[0])
    let at = await AppToken.at(app_token_proxy_address2);
    await at.claim();

    let appBalance = (await at.balanceOf(accounts[0])).toNumber();
    let estimatedPayout = (await rt.currentEstimatedPayout()).toNumber() / PRECISION;

    assert.strictEqual(
      appBalance,
      Math.floor(amountToGetS + amountToGetR * estimatedPayout),
      'Invalid claimed balance'
    );
  });
});
