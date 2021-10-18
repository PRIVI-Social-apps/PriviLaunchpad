const AppFundingManager = artifacts.require('AppFundingManager');
const RangeToken = artifacts.require('RangeToken');
const SyntheticToken = artifacts.require('SyntheticToken');
const AppToken = artifacts.require('AppToken');
const FundingTokenMock = artifacts.require('FundingTokenMock');
const WithdrawManager = artifacts.require('WithdrawManager');

const { expectEvent, expectRevert, time } = require('@openzeppelin/test-helpers');
const { getData, updateTimesOf } = require('../fabric');

const IPFS_HASH = 'QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB';

contract('AppFundingManager', function (accounts) {
  let app_funding_manager;
  let withdraw_manager;
  let range_token;
  let synthetic_token;
  let app_token;
  let funding_token;

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
  });

  describe('initialize app funding', () => {
    it("can't initialize without owners", async () => {
      let appDataWithoutOwners = { ...appData };
      appDataWithoutOwners.owners = [];
      await expectRevert(
        app_funding_manager.initializeAppFunding(appDataWithoutOwners, 'Test App Token', 'TAT', IPFS_HASH, {
          from: accounts[1],
        }),
        'No owners'
      );
    });

    it('initialize app funding (emit event)', async () => {
      let tx = app_funding_manager.initializeAppFunding(appData, 'Test App Token', 'TAT', IPFS_HASH, {
        from: accounts[1],
      });
      expectEvent(await tx, 'CreateApp', {
        id: '1',
      });
    });

    it('initialize app funding with right owners', async () => {
      await app_funding_manager.initializeAppFunding(appData, 'Test App Token', 'TAT', IPFS_HASH, {
        from: accounts[1],
      });

      // the app id is 1 (the first one)
      let owners = await app_funding_manager.getOwnersOf(1);

      assert.strictEqual(owners.length, appData.owners.length, 'Invalid owners length');
      assert.strictEqual(owners[0], appData.owners[0], 'Invalid owner');
      assert.strictEqual(owners[1], appData.owners[1], 'Invalid owner');
      assert.strictEqual(owners[2], appData.owners[2], 'Invalid owner');
    });

    it('can get app', async () => {
      await app_funding_manager.initializeAppFunding(appData, 'Test App Token', 'TAT', IPFS_HASH, {
        from: accounts[1],
      });

      // the app id is 1 (the first one)
      let app = await app_funding_manager.getApp(1);

      assert.ok(app.fundingTokenAddress, 'Invalid funding token address');
      assert.ok(app.appTokenAddress, 'Invalid app token address');
      assert.ok(app.syntheticTokenAddress, 'Invalid synthetic token address');
      assert.ok(app.rangeTokenAddress, 'Invalid range token address');
    });
  });

  describe('general functionalities', () => {
    it('can get owner index', async () => {
      await app_funding_manager.initializeAppFunding(appData, 'Test App Token', 'TAT', IPFS_HASH, {
        from: accounts[1],
      });

      // the app id is 1 (the first one)
      let result = await app_funding_manager.getOwnerIndexAndOwnersCount(appData.owners[2], 1);

      assert.strictEqual(result[0].toNumber(), 2, 'Invalid owner index');
      assert.strictEqual(result[1].toNumber(), appData.owners.length, 'Invalid owners length');
    });

    it("can't convert tokens before expiration date", async () => {
      await app_funding_manager.initializeAppFunding(appData, 'Test App Token', 'TAT', IPFS_HASH, {
        from: accounts[1],
      });

      // the app id is 1 (the first one)
      await expectRevert(app_funding_manager.convertTokens(1, appData.owners[2]), 'Invalid date');
    });

    it("can't convert tokens directly", async () => {
      let appDataWithoutOwners = { ...appData };

      await app_funding_manager.initializeAppFunding(appDataWithoutOwners, 'Test App Token', 'TAT', IPFS_HASH, {
        from: accounts[1],
      });

      // reach unlock date (15 days in future)
      await time.increase(time.duration.days(15));

      // the app id is 1 (the first one)
      await expectRevert(app_funding_manager.convertTokens(1, appData.owners[2]), 'Invalid call');
    });
  });
});
