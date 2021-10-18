// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./ScopeToken.sol";
import "./StakeToken.sol";
import "./Insurance.sol";
import "./oracles/OracleStructs.sol";
import "./oracles/SPOracle.sol";

/**
 * @title token funding contracts deployer and manager
 * @author Eric Nordelo
 */
contract TokenFundingManager is AccessControl, Pausable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenFundingIds;

    uint256 private constant PRECISION = 1000000;
    bytes32 private constant PRICE_ORACLE = keccak256("PRICE_ORACLE");
    bytes32 private constant ADMIN = keccak256("ADMIN");

    address public immutable withdrawManagerAddress;
    address public immutable insuranceImplementationAddress;
    address public immutable scopeTokenImplementationAddress;
    address public immutable stakeTokenImplementationAddress;
    address public immutable priceOracleImplementationAddress;

    mapping(uint256 => TokenFunding) private _tokenFundings;
    mapping(uint256 => address[]) private _tokenFundingsOwners;

    event CreateTokenFunding(
        uint256 id,
        address insuranceAddress,
        address stakeTokenAddress,
        address scopeTokenAddress,
        address priceOracleAddress
    );

    /**
     * @notice assign the default roles
     * @param _withdrawManagerAddress implementation to clone
     * @param _scopeTokenImplementationAddress implementation to clone
     * @param _stakeTokenImplementationAddress implementation to clone
     * @param _insuranceImplementationAddress implementation to clone
     * @param _priceOracleImplementationAddress implementation to clone
     */
    constructor(
        address _withdrawManagerAddress,
        address _scopeTokenImplementationAddress,
        address _stakeTokenImplementationAddress,
        address _insuranceImplementationAddress,
        address _priceOracleImplementationAddress
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN, msg.sender);

        withdrawManagerAddress = _withdrawManagerAddress;
        scopeTokenImplementationAddress = _scopeTokenImplementationAddress;
        stakeTokenImplementationAddress = _stakeTokenImplementationAddress;
        insuranceImplementationAddress = _insuranceImplementationAddress;
        priceOracleImplementationAddress = _priceOracleImplementationAddress;
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
     * @notice deploys tokens for this tokenFunding funding
     * @param tokenFundingData the data of the token to fund
     * @param _priceOracleInfo the struct with the data to initialize the oracles
     * @param _unstakeFee this value should be between 1 and FEE_PRECISION (1000)
     */
    function initializeTokenFunding(
        TokenFundingData calldata tokenFundingData,
        PriceOracleInfo calldata _priceOracleInfo,
        uint256 _unstakeFee
    ) external whenNotPaused {
        require(tokenFundingData.owners.length > 0, "No owners");
        require(tokenFundingData.t > block.timestamp, "Invalid unlock date"); // solhint-disable-line
        require(tokenFundingData.maturity > block.timestamp, "Invalid maturity date"); // solhint-disable-line
        require(tokenFundingData.rMin < tokenFundingData.rMax, "Invalid r interval");

        uint256 roundsCount = tokenFundingData.fundingScopeRoundsData.length;

        require(
            tokenFundingData.fundingScopeRoundsData[roundsCount - 1].openingTime +
                tokenFundingData.fundingScopeRoundsData[roundsCount - 1].durationTime <
                tokenFundingData.maturity,
            "Invalid dates"
        );

        // timestamps for oracle
        ScopeTimestamps memory timestamps = ScopeTimestamps({
            firstGSlabOpeningDate: tokenFundingData.fundingScopeRoundsData[0].openingTime,
            lastGSlabEndingDate: tokenFundingData.fundingScopeRoundsData[roundsCount - 1].openingTime +
                tokenFundingData.fundingScopeRoundsData[roundsCount - 1].durationTime,
            maturityDate: uint64(tokenFundingData.maturity)
        });

        _tokenFundingIds.increment();

        // deploys a minimal proxy contract from implementation
        address newInsurance = Clones.clone(insuranceImplementationAddress);

        address newPriceOracle = Clones.clone(priceOracleImplementationAddress);
        SPOracle(newPriceOracle).initialize(
            _priceOracleInfo.appToken,
            _priceOracleInfo,
            timestamps,
            tokenFundingData.owners
        );

        address newScopeToken = Clones.clone(scopeTokenImplementationAddress);
        ScopeToken(newScopeToken).initialize(
            "Privi Scope Token",
            "pRT",
            tokenFundingData,
            newInsurance,
            newPriceOracle
        );

        address newStakeToken = Clones.clone(stakeTokenImplementationAddress);
        StakeToken(newStakeToken).initialize(
            "Privi Stake Token",
            "pST",
            tokenFundingData,
            newInsurance,
            _unstakeFee
        );

        // intialize the insurance proxy with the token addresses
        Insurance(newInsurance).initialize(
            tokenFundingData.appToken,
            newStakeToken,
            newScopeToken,
            withdrawManagerAddress,
            tokenFundingData.maturity,
            tokenFundingData.t
        );

        _tokenFundings[_tokenFundingIds.current()] = TokenFunding({
            appTokenAddress: tokenFundingData.appToken,
            insuranceAddress: newInsurance,
            stakeTokenAddress: newStakeToken,
            scopeTokenAddress: newScopeToken
        });

        _tokenFundingsOwners[_tokenFundingIds.current()] = tokenFundingData.owners;

        emit CreateTokenFunding(
            _tokenFundingIds.current(),
            newInsurance,
            newStakeToken,
            newScopeToken,
            newPriceOracle
        );
    }

    /**
     * @notice getter for the owners of a token funding
     */
    function getOwnersOf(uint256 _tokenFundingId) external view returns (address[] memory) {
        require(_tokenFundings[_tokenFundingId].appTokenAddress != address(0), "Unexistent app");
        return _tokenFundingsOwners[_tokenFundingId];
    }

    /**
     * @param _owner The address of the owner to look for
     * @param _tokenFundingId The id of the token funding
     * @return The index and the owners count
     */
    function getOwnerIndexAndOwnersCount(address _owner, uint256 _tokenFundingId)
        external
        view
        returns (int256, uint256)
    {
        require(_tokenFundings[_tokenFundingId].appTokenAddress != address(0), "Unexistent token funding");

        uint256 count = _tokenFundingsOwners[_tokenFundingId].length;
        for (uint256 i = 0; i < count; i++) {
            if (_tokenFundingsOwners[_tokenFundingId][i] == _owner) {
                return (int256(i), count);
            }
        }
        return (-1, count);
    }

    /**
     * @notice getter for tokenFundings
     * @param _tokenFundingId the id of the tokenFunding to get
     */
    function getTokenFunding(uint256 _tokenFundingId) public view returns (TokenFunding memory) {
        require(_tokenFundings[_tokenFundingId].appTokenAddress != address(0), "Unexistent token funding");
        return _tokenFundings[_tokenFundingId];
    }
}
