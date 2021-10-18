// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./RangeToken.sol";
import "./AppToken.sol";
import "./SyntheticToken.sol";

/**
 * @title app funding contracts deployer and manager
 * @author Eric Nordelo
 */
contract AppFundingManager is AccessControl, Pausable {
    using Counters for Counters.Counter;

    Counters.Counter private _appIds;

    uint256 public constant PRECISION = 1000000;
    bytes32 public constant ADMIN = keccak256("admin");

    address public immutable withdrawManagerAddress;
    address public immutable rangeTokenImplementationAddress;
    address public immutable syntheticTokenImplementationAddress;
    address public immutable appTokenImplementationAddress;

    mapping(uint256 => App) private _apps;
    mapping(uint256 => address[]) private _appOwners;

    event CreateApp(
        uint256 id,
        address appTokenAddress,
        address syntheticTokenAddress,
        address rangeTokenAddress
    );

    /**
     * @notice assign the default roles
     * @param _withdrawManagerAddress implementation to clone
     * @param _rangeTokenImplementationAddress implementation to clone
     * @param _syntheticTokenImplementationAddress implementation to clone
     * @param _appTokenImplementationAddress implementation to clone
     */
    constructor(
        address _withdrawManagerAddress,
        address _rangeTokenImplementationAddress,
        address _syntheticTokenImplementationAddress,
        address _appTokenImplementationAddress
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN, msg.sender);

        withdrawManagerAddress = _withdrawManagerAddress;
        rangeTokenImplementationAddress = _rangeTokenImplementationAddress;
        syntheticTokenImplementationAddress = _syntheticTokenImplementationAddress;
        appTokenImplementationAddress = _appTokenImplementationAddress;
    }

    /**
     * @notice allows admins to pause the contract
     */
    function pause() external onlyRole(ADMIN) {
        _pause();
    }

    /**
     * @notice allows admins to unpause the contract
     */
    function unpause() external onlyRole(ADMIN) {
        _unpause();
    }

    /**
     * @notice deploys tokens for this app funding
     */
    function initializeAppFunding(
        AppFundingData calldata appData,
        string calldata appTokenName,
        string calldata appTokenSymbol,
        string calldata ipfsHashForLogo
    ) external whenNotPaused {
        require(appData.owners.length > 0, "No owners");
        require(appData.t >= block.timestamp, "Invalid unlock date"); // solhint-disable-line

        _appIds.increment();
        uint256 appId = _appIds.current();
        uint256 launchingDate = appData.t;

        // deploys a minimal proxy contract from implementation
        address newRangeToken = Clones.clone(rangeTokenImplementationAddress);
        RangeToken(newRangeToken).initialize("Privi Range Token", "pRT", appData, withdrawManagerAddress);

        address newSyntheticToken = Clones.clone(syntheticTokenImplementationAddress);
        SyntheticToken(newSyntheticToken).initialize(
            "Privi Synthetic Token",
            "pST",
            appData,
            withdrawManagerAddress
        );

        address newAppToken = Clones.clone(appTokenImplementationAddress);
        AppToken(newAppToken).initialize(appTokenName, appTokenSymbol, ipfsHashForLogo, appId, launchingDate);

        _apps[appId] = App({
            fundingTokenAddress: appData.fundingToken,
            appTokenAddress: newAppToken,
            syntheticTokenAddress: newSyntheticToken,
            rangeTokenAddress: newRangeToken
        });

        _appOwners[appId] = appData.owners;

        emit CreateApp(appId, newAppToken, newSyntheticToken, newRangeToken);
    }

    /**
     * @notice getter for the owners of an app
     */
    function getOwnersOf(uint256 _appId) external view returns (address[] memory) {
        require(_apps[_appId].appTokenAddress != address(0), "Unexistent app");
        return _appOwners[_appId];
    }

    /**
     * @param _owner The address of the owner to look for
     * @param _appId The id of the app
     * @return The index and the owners count
     */
    function getOwnerIndexAndOwnersCount(address _owner, uint256 _appId)
        external
        view
        returns (int256, uint256)
    {
        require(_apps[_appId].appTokenAddress != address(0), "Unexistent app");

        uint256 count = _appOwners[_appId].length;
        for (uint256 i = 0; i < count; i++) {
            if (_appOwners[_appId][i] == _owner) {
                return (int256(i), count);
            }
        }
        return (-1, count);
    }

    /**
     * @notice helper for app tokens claims
     */
    function convertTokens(uint256 _appId, address _holder) external returns (uint256) {
        App memory app = getApp(_appId);

        // solhint-disable-next-line
        require(RangeToken(app.rangeTokenAddress).maturityDate() <= block.timestamp, "Invalid date");

        // only the app token contract of the app can call this helper
        require(app.appTokenAddress == msg.sender, "Invalid call");

        uint256 holderSyntheticBalance = SyntheticToken(app.syntheticTokenAddress).balanceOf(_holder);
        (uint256 holderRangeTokenBalance, uint256 payout) = RangeToken(app.rangeTokenAddress)
            .balanceAndPayoutOf(_holder);

        // the payout comes multiplied for the precision
        uint256 holderBalance = holderSyntheticBalance + ((holderRangeTokenBalance * payout) / PRECISION);

        require(holderBalance > 0, "No tokens to claim");

        // make the convertion
        if (holderSyntheticBalance > 0) {
            SyntheticToken(app.syntheticTokenAddress).burn(_holder, holderSyntheticBalance);
        }
        if (holderRangeTokenBalance > 0) {
            RangeToken(app.rangeTokenAddress).burn(_holder, holderRangeTokenBalance);
        }
        AppToken(app.appTokenAddress).mint(_holder, holderBalance);

        return holderBalance;
    }

    /**
     * @notice getter for apps
     * @param _appId the id of the app to get
     */
    function getApp(uint256 _appId) public view returns (App memory) {
        require(_apps[_appId].appTokenAddress != address(0), "Unexistent app");
        return _apps[_appId];
    }
}
