// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./AppFundingManager.sol";
import "./IWithdrawable.sol";
import "./Structs.sol";

/**
 * @title manager for withdrawals
 * @author Eric Nordelo
 * @notice manages the withdrawals proposals and the multisig logic
 */
contract WithdrawManager is AccessControl, Initializable {
    using Counters for Counters.Counter;

    Counters.Counter private _withdrawProposalIds;

    uint64 private constant PROPOSAL_DURATION = 1 weeks;

    address public appFundingManagerAddress;

    // map from Id to WithdrawProposal
    mapping(uint256 => WithdrawProposal) private _withdrawProposals;
    // stores a mapping of owners and if already voted by proposalId
    mapping(uint256 => mapping(address => bool)) private _withdrawProposalsVoted;

    event DirectWithdraw(uint256 indexed tokenFundingId, address indexed recipient, uint256 amount);
    event CreateWithdrawProposal(
        uint256 indexed appId,
        address indexed recipient,
        uint256 amount,
        uint256 indexed proposalId
    );
    event ApproveWithdrawProposal(
        uint256 indexed appId,
        address indexed recipient,
        uint256 amount,
        uint256 indexed proposalId
    );
    event DenyWithdrawProposal(
        uint256 indexed appId,
        address indexed recipient,
        uint256 amount,
        uint256 indexed proposalId
    );
    event VoteWithdrawProposal(address indexed voter, uint256 indexed appId, uint256 indexed proposalId);
    event ExpireWithdrawProposal(
        uint256 indexed appId,
        address indexed recipient,
        uint256 amount,
        uint256 indexed proposalId
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice sets the addresses to support integration
     * @param _appFundingManagerAddress the address of the Privi NFT contract
     */
    function initialize(address _appFundingManagerAddress) external initializer onlyRole(DEFAULT_ADMIN_ROLE) {
        appFundingManagerAddress = _appFundingManagerAddress;
    }

    /**
     * @notice direct withdraw when there is only one owner
     * @param _recipient the recipient of the transfer
     * @param _appId the token funding id
     * @param _amount the amount of the app tokens to withdraw
     * @param _fromRangeTokenContract selects which contract should be extracted from
     */
    function withdrawTo(
        address _recipient,
        uint256 _appId,
        uint256 _amount,
        bool _fromRangeTokenContract
    ) external {
        (int256 index, uint256 ownersCount) = AppFundingManager(appFundingManagerAddress)
            .getOwnerIndexAndOwnersCount(msg.sender, _appId);

        require(index >= 0, "Invalid requester");
        require(ownersCount == 1, "Multiple owners, voting is needed");

        App memory app = AppFundingManager(appFundingManagerAddress).getApp(_appId);

        // make the transfer
        address contractAddress = _fromRangeTokenContract ? app.rangeTokenAddress : app.syntheticTokenAddress;

        require(
            IWithdrawable(contractAddress).withdrawTo(_recipient, _amount, app.fundingTokenAddress),
            "Error at transfer"
        );

        emit DirectWithdraw(_appId, _recipient, _amount);
    }

    /**
     * @notice create a proposal for withdraw funds
     * @param _recipient the recipient of the transfer
     * @param _appId the app id
     * @param _amount the amount of the funding token to withdraw
     */
    function createWithdrawProposal(
        address _recipient,
        uint256 _appId,
        uint256 _amount,
        bool _fromRangeTokenContract
    ) external {
        _withdrawProposalIds.increment();

        uint256 proposalId = _withdrawProposalIds.current();

        (int256 index, uint256 ownersCount) = AppFundingManager(appFundingManagerAddress)
            .getOwnerIndexAndOwnersCount(msg.sender, _appId);
        require(index >= 0, "Invalid requester");
        require(ownersCount > 1, "Only one owner, voting is not needed");

        WithdrawProposal memory _withdrawProposal = WithdrawProposal({
            minApprovals: uint64(ownersCount),
            maxDenials: 1,
            positiveVotesCount: 0,
            negativeVotesCount: 0,
            appId: _appId,
            recipient: _recipient,
            amount: _amount,
            date: uint64(block.timestamp), // solhint-disable-line
            duration: PROPOSAL_DURATION,
            fromRangeTokenContract: _fromRangeTokenContract
        });

        // save the proposal for voting
        _withdrawProposals[proposalId] = _withdrawProposal;

        emit CreateWithdrawProposal(_appId, _recipient, _amount, proposalId);
    }

    /**
     * @notice allows owners to vote withdraw proposals for pods
     * @param _proposalId the id of the withdraw proposal
     * @param _vote the actual vote: true or false
     */
    function voteWithdrawProposal(uint256 _proposalId, bool _vote) external {
        require(_withdrawProposals[_proposalId].minApprovals != 0, "Unexistent proposal");

        WithdrawProposal memory withdrawProposal = _withdrawProposals[_proposalId];

        (int256 index, ) = AppFundingManager(appFundingManagerAddress).getOwnerIndexAndOwnersCount(
            msg.sender,
            withdrawProposal.appId
        );

        require(index >= 0, "Invalid owner");

        require(!_withdrawProposalsVoted[_proposalId][msg.sender], "Owner already voted");

        _withdrawProposalsVoted[_proposalId][msg.sender] = true;

        // check if expired
        // solhint-disable-next-line
        if (withdrawProposal.date + withdrawProposal.duration < block.timestamp) {
            // delete the recover gas
            delete _withdrawProposals[_proposalId];
            emit ExpireWithdrawProposal(
                withdrawProposal.appId,
                withdrawProposal.recipient,
                withdrawProposal.amount,
                _proposalId
            );
        } else {
            // if the vote is positive
            if (_vote) {
                // if is the last vote to approve
                if (withdrawProposal.positiveVotesCount + 1 == withdrawProposal.minApprovals) {
                    delete _withdrawProposals[_proposalId];

                    App memory app = AppFundingManager(appFundingManagerAddress).getApp(
                        withdrawProposal.appId
                    );

                    // make the transfer
                    address contractAddress = withdrawProposal.fromRangeTokenContract
                        ? app.rangeTokenAddress
                        : app.syntheticTokenAddress;

                    require(
                        IWithdrawable(contractAddress).withdrawTo(
                            withdrawProposal.recipient,
                            withdrawProposal.amount,
                            app.fundingTokenAddress
                        ),
                        "Error at transfer"
                    );

                    emit ApproveWithdrawProposal(
                        withdrawProposal.appId,
                        withdrawProposal.recipient,
                        withdrawProposal.amount,
                        _proposalId
                    );
                } else {
                    // update the proposal and emit the event
                    _withdrawProposals[_proposalId].positiveVotesCount++;
                    emit VoteWithdrawProposal(msg.sender, withdrawProposal.appId, _proposalId);
                }
            }
            // if the vote is negative
            else {
                // if is the last vote to deny
                if (withdrawProposal.negativeVotesCount + 1 == withdrawProposal.maxDenials) {
                    // delete the proposal and emit the event
                    delete _withdrawProposals[_proposalId];
                    emit DenyWithdrawProposal(
                        withdrawProposal.appId,
                        withdrawProposal.recipient,
                        withdrawProposal.amount,
                        _proposalId
                    );
                } else {
                    // update the proposal and emit the event
                    _withdrawProposals[_proposalId].negativeVotesCount++;
                    emit VoteWithdrawProposal(msg.sender, withdrawProposal.appId, _proposalId);
                }
            }
        }
    }

    /**
     * @notice proposal struct getter
     * @param _proposalId The id of the withdraw proposal
     * @return the WithdrawProposal object
     */
    function getUpdateMediaProposal(uint256 _proposalId) external view returns (WithdrawProposal memory) {
        WithdrawProposal memory withdrawProposal = _withdrawProposals[_proposalId];
        require(withdrawProposal.minApprovals != 0, "Unexistent proposal");
        return withdrawProposal;
    }
}
