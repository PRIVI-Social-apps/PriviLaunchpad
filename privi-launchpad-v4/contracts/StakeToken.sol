// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./Insurance.sol";
import "./Structs.sol";

/**
 * @notice implementation of the stake token for minimal proxy multiple deployments
 * @author Eric Nordelo
 */
contract StakeToken is ERC721, AccessControl, Initializable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    uint256 private constant PRECISION = 1000000;
    uint256 private constant REWARD_PRECISION = 1000;
    uint256 private constant FEE_PRECISION = 1000;

    string private _proxiedName;
    string private _proxiedSymbol;

    FundingStakeRoundsData[] private _fundingRoundsData;

    address private _appToken;
    address private _insuranceContractAddress;

    uint128 public expirationDate; // date of expiration of the options
    uint128 public unstakeFee = 50; // value between 1 and FEE_PRECISION

    mapping(uint256 => uint256) public tokensRewards;
    mapping(uint256 => uint256) public tokensRoundIndex;
    mapping(uint256 => uint256) public appTokensStaked;

    /**
     * @notice getters for total staked and owed values in app tokens
     */
    uint256 public appTokensOwed;
    uint256 public totalAppTokensStaked;

    event StakeTokens(address indexed holder, uint256 nftId, uint256 quantity);
    event ClaimTokens(address indexed holder, uint256 quantity);
    event UnstakeTokens(address indexed holder, uint256 quantityStaked, uint256 quantityReceivedAfterFee);

    // solhint-disable-next-line
    constructor() ERC721("Privi Stake Token", "pST") {}

    /**
     * @notice initializes minimal proxy clone
     */
    function initialize(
        string calldata proxiedName,
        string calldata proxiedSymbol,
        TokenFundingData calldata _tokenFundingData,
        address __insuranceContractAddress,
        uint256 _unstakeFee
    ) external initializer {
        _proxiedName = proxiedName;
        _proxiedSymbol = proxiedSymbol;
        _appToken = _tokenFundingData.appToken;
        _insuranceContractAddress = __insuranceContractAddress;

        expirationDate = _tokenFundingData.t;

        if (_unstakeFee < 1 || _unstakeFee > FEE_PRECISION) {
            revert("Fee should be between 1 and FEE_PRECISION");
        }
        unstakeFee = uint128(_unstakeFee);

        require(_tokenFundingData.fundingStakeRoundsData.length > 0, "Invalid rounds count");
        for (uint256 i; i < _tokenFundingData.fundingStakeRoundsData.length - 1; i++) {
            require(_tokenFundingData.fundingStakeRoundsData[i].stakedTokens == 0, "Invalid data");
            if (
                _tokenFundingData.fundingStakeRoundsData[i].stakeReward <
                _tokenFundingData.fundingStakeRoundsData[i + 1].stakeReward ||
                _tokenFundingData.fundingStakeRoundsData[i].stakeReward == 0
            ) {
                revert("Invalid rewards distribution");
            }
            _fundingRoundsData.push(_tokenFundingData.fundingStakeRoundsData[i]);
        }
        _fundingRoundsData.push(
            _tokenFundingData.fundingStakeRoundsData[_tokenFundingData.fundingStakeRoundsData.length - 1]
        );

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function name() public view virtual override returns (string memory) {
        return _proxiedName;
    }

    function symbol() public view virtual override returns (string memory) {
        return _proxiedSymbol;
    }

    /**
     * @notice allows to get the accrued reward of staked tokens
     * @param _tokenId the is of the nft token
     */
    function getAccruedReward(uint256 _tokenId) external view returns (uint256 accruedReward) {
        uint256 _roundId = tokensRoundIndex[_tokenId];
        require(_roundId != 0, "Unexistent token");

        // the index is the id minus 1
        uint256 roundEndingDate = _fundingRoundsData[_roundId - 1].openingTime +
            _fundingRoundsData[_roundId - 1].durationTime;

        // solhint-disable-next-line
        if (block.timestamp <= roundEndingDate) {
            return 0;
        }

        // apply the formula
        accruedReward =
            (((appTokensStaked[_tokenId] * _fundingRoundsData[_roundId - 1].stakeReward) / REWARD_PRECISION) *
                (block.timestamp - roundEndingDate)) / // solhint-disable-line
            (expirationDate - roundEndingDate);
    }

    /**
     * @notice allows an account to stake app tokens in the contract
     * @param _amount the amount of app tokens to stake
     */
    function stake(uint256 _amount) external {
        require(_amount > 0, "Invalid amount");
        require(
            IERC20(_appToken).transferFrom(msg.sender, _insuranceContractAddress, _amount),
            "Allowance required"
        );

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        uint256 reward = getCurrentReward();

        uint256 _roundId = getRoundNumber();
        tokensRoundIndex[newTokenId] = _roundId;

        tokensRewards[newTokenId] = reward;
        appTokensStaked[newTokenId] = _amount;

        // update the total staked and owed valued
        totalAppTokensStaked += _amount;
        appTokensOwed += _amount + ((_amount * reward) / REWARD_PRECISION);

        _mint(msg.sender, newTokenId);

        emit StakeTokens(msg.sender, newTokenId, _amount);
    }

    /**
     * @notice allows to claim the app tokens before time (without rewards and paying fee)
     */
    function unstake(uint256 _tokenId) external {
        // solhint-disable-next-line
        require(expirationDate > block.timestamp, "Expiration date reached");
        require(msg.sender == ownerOf(_tokenId), "User doesn't own the token");

        uint256 stakedAmount = appTokensStaked[_tokenId];
        uint256 reward = tokensRewards[_tokenId];

        assert(stakedAmount > 0);

        uint256 appTokensToReceive = stakedAmount - ((stakedAmount * unstakeFee) / FEE_PRECISION);

        delete appTokensStaked[_tokenId];
        delete tokensRoundIndex[_tokenId];
        delete tokensRewards[_tokenId];

        // update the total staked and owed valued
        totalAppTokensStaked -= stakedAmount;
        appTokensOwed -= stakedAmount + ((stakedAmount * reward) / REWARD_PRECISION);

        // burn the tokens before transfer
        _burn(_tokenId);

        // send the tokens from payout
        bool transfered = Insurance(_insuranceContractAddress).sendAppTokens(msg.sender, appTokensToReceive);
        require(transfered, "Fail to transfer");

        emit UnstakeTokens(msg.sender, stakedAmount, appTokensToReceive);
    }

    /**
     * @notice allows to claim the app tokens at the right time
     */
    function claim(uint256 _tokenId) external {
        // solhint-disable-next-line
        require(expirationDate <= block.timestamp, "Expiration date not reached yet");
        require(msg.sender == ownerOf(_tokenId), "User doesn't own the token");

        uint256 stakedAmount = appTokensStaked[_tokenId];
        uint256 reward = tokensRewards[_tokenId];

        assert(stakedAmount > 0);

        uint256 appTokensToReceive = stakedAmount + ((stakedAmount * reward) / REWARD_PRECISION);

        delete appTokensStaked[_tokenId];
        delete tokensRoundIndex[_tokenId];
        delete tokensRewards[_tokenId];

        // update the total staked and owed valued
        totalAppTokensStaked -= stakedAmount;
        appTokensOwed -= stakedAmount + ((stakedAmount * reward) / REWARD_PRECISION);

        // burn the tokens before transfer
        _burn(_tokenId);

        // send the tokens from payout
        bool transfered = Insurance(_insuranceContractAddress).sendAppTokens(msg.sender, appTokensToReceive);
        require(transfered, "Fail to transfer");

        emit ClaimTokens(msg.sender, appTokensToReceive);
    }

    /**
     * @notice returns the current round number
     */
    function getRoundNumber() public view returns (uint256) {
        // solhint-disable-next-line
        uint256 currentTime = block.timestamp;
        if (
            currentTime < _fundingRoundsData[0].openingTime ||
            currentTime >
            _fundingRoundsData[_fundingRoundsData.length - 1].openingTime +
                _fundingRoundsData[_fundingRoundsData.length - 1].durationTime *
                1 days
        ) {
            return 0;
        }
        for (uint256 i; i < _fundingRoundsData.length; i++) {
            if (
                currentTime >= _fundingRoundsData[i].openingTime &&
                currentTime < _fundingRoundsData[i].openingTime + _fundingRoundsData[i].durationTime * 1 days
            ) {
                return i + 1;
            }
        }
        return 0;
    }

    /**
     * @notice get current reward of staking (REWARD_PRECISION should be divided to returned value)
     */
    function getCurrentReward() public view returns (uint256) {
        uint256 _roundId = getRoundNumber();
        require(_roundId != 0, "None open round");

        // the index is the id minus 1
        return _fundingRoundsData[_roundId - 1].stakeReward;
    }

    /**
     * @dev disallows transfer functionality
     */
    function _transfer(
        address,
        address,
        uint256
    ) internal pure override {
        revert("Transfer not allowed");
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
