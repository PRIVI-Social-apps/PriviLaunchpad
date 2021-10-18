const AppFundingManager = artifacts.require('AppFundingManager');
const RangeToken = artifacts.require('RangeToken');
const SyntheticToken = artifacts.require('SyntheticToken');
const AppToken = artifacts.require('AppToken');
const FundingTokenMock = artifacts.require('FundingTokenMock');
const WithdrawManager = artifacts.require('WithdrawManager');

const { expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { getData, updateTimesOf } = require('../fabric');

const IPFS_HASH = 'QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB';

contract('WithdrawManager', function (accounts) {
  let app_funding_manager;
  let withdraw_manager;
  let range_token;
  let synthetic_token;
  let app_token;
  let funding_token;
  let synthetic_token_proxy_address;
  let range_token_proxy_address;

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
  });

  describe('withdraw funds (transfering)', () => {
    it('can propose withdrawal, vote and transfer (range token)', async () => {
      // get range tokens
      let rt = await RangeToken.at(range_token_proxy_address);
      let roundPriceR = await rt.getTokenPrice();
      let amountToGetR = 5;

      await funding_token.approve(rt.address, roundPriceR * amountToGetR, { from: accounts[0] });
      await rt.buyTokensByAmountToGet(amountToGetR, { from: accounts[0] });

      let rtBalance = await funding_token.balanceOf(rt.address);

      expectEvent(
        await withdraw_manager.createWithdrawProposal(accounts[3], 1, rtBalance, true, { from: accounts[2] }),
        'CreateWithdrawProposal',
        { appId: '1', recipient: accounts[3], amount: String(rtBalance), proposalId: '1' }
      );

      expectEvent(await withdraw_manager.voteWithdrawProposal(1, true, { from: accounts[2] }), 'VoteWithdrawProposal', {
        voter: accounts[2],
        appId: '1',
        proposalId: '1',
      });

      expectEvent(await withdraw_manager.voteWithdrawProposal(1, true, { from: accounts[1] }), 'VoteWithdrawProposal', {
        voter: accounts[1],
        appId: '1',
        proposalId: '1',
      });

      expectEvent(
        await withdraw_manager.voteWithdrawProposal(1, true, { from: accounts[0] }),
        'ApproveWithdrawProposal',
        {
          recipient: accounts[3],
          appId: '1',
          amount: rtBalance,
          proposalId: '1',
        }
      );

      balance = await funding_token.balanceOf(accounts[3]);

      assert.strictEqual(balance.toNumber(), rtBalance.toNumber());
    });

    it('can propose withdrawal, vote and transfer (synthetic token)', async () => {
      // get synthetic tokens
      let st = await SyntheticToken.at(synthetic_token_proxy_address);
      let roundPriceS = await st.getTokenPrice();
      let amountToGetS = 7;

      await funding_token.approve(st.address, roundPriceS * amountToGetS, { from: accounts[0] });
      await st.buyTokensByAmountToGet(amountToGetS, { from: accounts[0] });

      let stBalance = await funding_token.balanceOf(st.address);

      expectEvent(
        await withdraw_manager.createWithdrawProposal(accounts[3], 1, stBalance, false, { from: accounts[2] }),
        'CreateWithdrawProposal',
        { appId: '1', recipient: accounts[3], amount: String(stBalance), proposalId: '1' }
      );

      expectEvent(await withdraw_manager.voteWithdrawProposal(1, true, { from: accounts[2] }), 'VoteWithdrawProposal', {
        voter: accounts[2],
        appId: '1',
        proposalId: '1',
      });

      expectEvent(await withdraw_manager.voteWithdrawProposal(1, true, { from: accounts[1] }), 'VoteWithdrawProposal', {
        voter: accounts[1],
        appId: '1',
        proposalId: '1',
      });

      expectEvent(
        await withdraw_manager.voteWithdrawProposal(1, true, { from: accounts[0] }),
        'ApproveWithdrawProposal',
        {
          recipient: accounts[3],
          appId: '1',
          amount: stBalance,
          proposalId: '1',
        }
      );

      balance = await funding_token.balanceOf(accounts[3]);

      assert.strictEqual(balance.toNumber(), stBalance.toNumber());
    });

    it('can propose withdrawal, vote and deny', async () => {
      // get synthetic tokens
      let st = await SyntheticToken.at(synthetic_token_proxy_address);
      let roundPriceS = await st.getTokenPrice();
      let amountToGetS = 7;

      await funding_token.approve(st.address, roundPriceS * amountToGetS, { from: accounts[0] });
      await st.buyTokensByAmountToGet(amountToGetS, { from: accounts[0] });

      // get range tokens
      let rt = await RangeToken.at(range_token_proxy_address);
      let roundPriceR = await rt.getTokenPrice();
      let amountToGetR = 5;

      await funding_token.approve(rt.address, roundPriceR * amountToGetR, { from: accounts[0] });
      await rt.buyTokensByAmountToGet(amountToGetR, { from: accounts[0] });

      let balance = await rt.balanceOf(accounts[0]);

      expectEvent(
        await withdraw_manager.createWithdrawProposal(accounts[3], 1, balance, { from: accounts[2] }),
        'CreateWithdrawProposal',
        { appId: '1', recipient: accounts[3], amount: String(balance), proposalId: '1' }
      );

      expectEvent(
        await withdraw_manager.voteWithdrawProposal(1, false, { from: accounts[1] }),
        'DenyWithdrawProposal',
        {
          recipient: accounts[3],
          appId: '1',
          amount: balance,
          proposalId: '1',
        }
      );

      await expectRevert(withdraw_manager.voteWithdrawProposal(1, true, { from: accounts[0] }), 'Unexistent proposal');
    });
  });
});
