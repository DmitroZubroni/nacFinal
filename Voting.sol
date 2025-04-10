// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Governor, GovernorVotesQuorumFraction, GovernorVotes, GovernorCountingSimple, IVotes} from "./GovernanceBundle.sol";
import {ProfiCoin, RTKCoin} from "./Tokens.sol";

contract MyGovernance is Governor, GovernorVotesQuorumFraction, GovernorCountingSimple {
    enum ProposeType { A, B, C, D, E, F }

    enum VoteStatus { NotStarted, Active, Approved, Rejected, Cancelled }
    
    enum QuorumMechanism { SimpleMajority, SuperMajority, Weighted }

    struct ProposeLib {
        uint256 proposeID;
        ProposeType proposeType;
        address proposer;
        uint48 voteStart;
        uint48 voteEnd;
        uint8 priority;
        string eventType;
        QuorumMechanism quorumType;
        VoteStatus status;
    }

    struct Vote {
        uint256 id;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
    }

    mapping(uint256 => Vote) private voteData;
    mapping(uint256 => ProposalVote) private _proposalVotes;
    mapping(uint256 => mapping(address => bool)) public customHasVoted;

    mapping(address => bool) public isMember;
    mapping(address => uint256) public delegatedRTK;

    ProposeLib[] private proposes;

    ProfiCoin public profiCoin;
    RTKCoin public rtkCoin;

    uint32 public delay = 0;
    uint48 public period = 12;

    modifier onlyMember() {
        require(isMember[msg.sender], unicode"Только участники DAO");
        _;
    }

    constructor(address tom, address ben, address rick, address jack, address _profiCoin, address _rtkCoin)
        Governor("DAO")
        GovernorVotes(IVotes(_profiCoin))
        GovernorVotesQuorumFraction(1)
    {
        profiCoin = ProfiCoin(_profiCoin);
        rtkCoin = RTKCoin(_rtkCoin);

        addMember(tom);
        addMember(ben);
        addMember(rick);

        profiCoin.delegate(tom);
        profiCoin.delegate(ben);
        profiCoin.delegate(rick);
        profiCoin.delegate(jack);

        rtkCoin.mint(address(this), 20_000_000 * 10 ** 12);
    }

    function votingDelay() public view override returns (uint256) {
        return delay;
    }

    function votingPeriod() public view override returns (uint256) {
        return period;
    }

    function addMember(address _member) internal {
        if (!isMember[_member]) {
            isMember[_member] = true;
        }
    }

    function buyToken(uint256 amount) external payable {
        require(amount * rtkCoin.price() <= msg.value, unicode"Недостаточно средств");
        rtkCoin.transfer(address(this), msg.sender, amount * 10 ** rtkCoin.decimals());
    }

    function _calculateVotingPower(address _member) private view returns (uint256) {
        uint256 profiPower = profiCoin.balanceOf(_member) / 3;
        uint256 rtkPower = (rtkCoin.balanceOf(_member) + delegatedRTK[_member]) / 6;
        return profiPower + rtkPower;
    }

    function setProposal(
        ProposeType proposeType,
        uint32 _delay,
        uint48 _period,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint8 priority,
        string memory eventType,
        QuorumMechanism quorumType
    ) external onlyMember returns (uint256) {
        delay = _delay;
        period = _period;

        uint256 ID = super.propose(targets, values, calldatas, description);

        proposes.push(ProposeLib({
            proposeID: ID,
            proposeType: proposeType,
            proposer: msg.sender,
            voteStart: clock(),
            voteEnd: clock() + _period,
            priority: priority,
            eventType: eventType,
            quorumType: quorumType,
            status: VoteStatus.Active
        }));

        voteData[ID] = Vote(ID, targets, values, calldatas, description);
        return ID;
    }

    function cancelProposal(uint256 proposalID) external onlyMember {
        ProposeLib storage prop = _getProposalById(proposalID);
        require(msg.sender == prop.proposer, unicode"Только инициатор может отменить");
        prop.status = VoteStatus.Cancelled;

        Vote storage v = voteData[proposalID];
        super.cancel(v.targets, v.values, v.calldatas, keccak256(abi.encodePacked("")));
    }

    function callExecute(uint256 proposalID) external onlyMember {
        ProposeLib storage prop = _getProposalById(proposalID);
        require(prop.status == VoteStatus.Active, unicode"Голосование не активно");

        Vote storage v = voteData[proposalID];
        super.execute(v.targets, v.values, v.calldatas, keccak256(abi.encodePacked("")));

        ProposalVote storage result = _proposalVotes[proposalID];

        bool approved = _checkQuorum(result, prop.quorumType);
        prop.status = approved ? VoteStatus.Approved : VoteStatus.Rejected;
    }

    function _checkQuorum(ProposalVote storage vote, QuorumMechanism qm) internal view returns (bool) {
        uint256 totalVotes = vote.forVotes + vote.againstVotes + vote.abstainVotes;
        if (qm == QuorumMechanism.SimpleMajority) {
            return vote.forVotes > vote.againstVotes;
        } else if (qm == QuorumMechanism.SuperMajority) {
            return vote.forVotes * 3 > totalVotes * 2; // 2/3
        } else {
            return vote.forVotes > 0; // весовой — любое количество достаточно
        }
    }

    function castVote(uint256 proposalId, uint8 support) public virtual override returns (uint256) {
        require(!customHasVoted[proposalId][msg.sender], unicode"Уже голосовал");
        customHasVoted[proposalId][msg.sender] = true;

        uint256 weight = _calculateVotingPower(msg.sender);
        ProposalVote storage pv = _proposalVotes[proposalId];

        if (support == uint8(VoteType.Against)) {
            pv.againstVotes += weight;
        } else if (support == uint8(VoteType.For)) {
            pv.forVotes += weight;
        } else if (support == uint8(VoteType.Abstain)) {
            pv.abstainVotes += weight;
        } else {
            revert("Invalid vote type");
        }

        return weight;
    }

    function delegateRTK(address to, uint256 amount) external {
        require(!isMember[msg.sender], unicode"Участники DAO не могут делегировать таким способом");
        require(isMember[to], unicode"Делегировать можно только участнику DAO");

        rtkCoin.transfer(msg.sender, to, amount);
        delegatedRTK[to] += amount;
    }

    function delegateProfiVotes(address to) external onlyMember {
        require(isMember[to], unicode"Только участнику DAO");
        profiCoin.delegate(to);
    }

    function getProposes() external view returns (ProposeLib[] memory) {
        return proposes;
    }

    function getProposal(uint256 proposalID) external view returns (Vote memory) {
        return voteData[proposalID];
    }

    function getBalance() external view returns (uint256 profi, uint256 rtk, uint256 eth) {
        return (
            profiCoin.balanceOf(msg.sender),
            rtkCoin.balanceOf(msg.sender),
            msg.sender.balance
        );
    }

    function _getProposalById(uint256 proposalID) internal view returns (ProposeLib storage) {
        for (uint256 i = 0; i < proposes.length; i++) {
            if (proposes[i].proposeID == proposalID) {
                return proposes[i];
            }
        }
        revert("Proposal not found");
    }
}
