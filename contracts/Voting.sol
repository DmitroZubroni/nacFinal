// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Governor, GovernorVotesQuorumFraction, GovernorVotes, GovernorCountingSimple, IVotes} from "./GovernanceBundle.sol";
import {ProfiCoin, RTKCoin} from "./Tokens.sol";

contract MyGovernance is Governor, GovernorVotesQuorumFraction, GovernorCountingSimple {
    
    // Типы предложений
    enum ProposeType { A, B, C, D, E, F }

    // Возможные статусы голосования
    enum VoteStatus { NotStarted, Active, Approved, Rejected, Cancelled }

    // Поддерживаемые механизмы кворума
    enum QuorumMechanism { SimpleMajority, SuperMajority, Weighted }

    // Структура, описывающая информацию о предложении
    struct ProposeLib {
        uint256 proposeID;
        ProposeType proposeType;
        address proposer;
        uint48 voteStart;
        uint48 voteEnd;
        QuorumMechanism quorumType;
        VoteStatus status;
    }

    // Структура, описывающая голосование
    struct Vote {
        uint256 id;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
    }

    // Маппинг ID предложения -> структура голосования
    mapping(uint256 => Vote) private voteData;

    // Маппинг ID предложения -> счетчик голосов
    mapping(uint256 => ProposalVote) private _proposalVotes;

    // Пользователь уже голосовал по предложению
    mapping(uint256 => mapping(address => bool)) public customHasVoted;

    // Членство в DAO
    mapping(address => bool) public isMember;

    // Делегированные RTK-токены для голосов
    mapping(address => uint256) public delegatedRTK;

    // Замена массива на маппинг
    mapping(uint256 => ProposeLib) private proposeMapping;


    // Инстансы токенов
    ProfiCoin public profiCoin;
    RTKCoin public rtkCoin;

    // Настройки голосования
    uint32 public delay = 0;
    uint48 public period = 12;

    // сила profi
    uint profiPower = 3;

    // сила wrap токена
    uint rtkPower = 6;

    /// @notice Ограничение: только участник DAO
    modifier onlyMember() {
        require(isMember[msg.sender], unicode"Только участники DAO");
        _;
    }

    // Конструктор: инициализация токенов, участников и делегирования
    constructor(address tom, address ben, address rick, address jack, address _profiCoin, address _rtkCoin)
        Governor("DAO")
        GovernorVotes(IVotes(_profiCoin))
        GovernorVotesQuorumFraction(1)
    {
        profiCoin = ProfiCoin(_profiCoin);
        rtkCoin = RTKCoin(_rtkCoin);

        // Добавляем участников DAO
        addMember(tom);
        addMember(ben);
        addMember(rick);

        // Делегируем системные токены
        profiCoin.delegate(tom);
        profiCoin.delegate(ben);
        profiCoin.delegate(rick);
        profiCoin.delegate(jack);

        // Выпускаем RTK-токены
        rtkCoin.mint(address(this), 20_000_000 * 10 ** 12);
    }

    //  Задержка перед голосованием
    function votingDelay() public view override returns (uint256) {
        return delay;
    }

    // Длительность голосования
    function votingPeriod() public view override returns (uint256) {
        return period;
    }

    // Добавить участника в DAO
    function addMember(address _member) internal {
        if (!isMember[_member]) {
            isMember[_member] = true;
        }
    }

    //  Удалить участника из DAO
    function removeMember(address _member) internal {
        require(isMember[_member], unicode"Участник не найден");
        isMember[_member] = false;
    }

    ///  Купить RTK-токены
    function buyToken(uint256 amount) external payable {
        require(amount * rtkCoin.price() <= msg.value, unicode"Недостаточно средств");
        rtkCoin.transfer(address(this), msg.sender, amount * 10 ** rtkCoin.decimals());
    }

    ///  Подсчет голосовой силы пользователя (PROFI и RTK)
    function _calculateVotingPower(address _member, uint amount) private view returns (uint256) {
        uint256 profiP = amount / profiPower;
        uint256 rtkP =( amount + delegatedRTK[_member]) / rtkPower;
        return profiP + rtkP;
    }

    // Установить новую силу голосования для PROFI
    function setProfiPower(uint256 newProfiPower) internal {
    profiPower = newProfiPower;
    }

    // Установить новую силу голосования для RTK
    function setRtkPower(uint256 newRtkPower) internal {
    rtkPower = newRtkPower;
    }

    
    function setProposal(uint32 _delay, uint48 _period, ProposeType proposeType, QuorumMechanism quorumType, bytes memory params
    ) external payable onlyMember returns (uint256) {
    // Устанавливаем параметры задержки и периода голосования
    delay = _delay;
    period = _period;

    address  [] memory targets = new address[](1); 
    uint [] memory values= new uint256 [](1); 
    bytes [] memory calldatas = new bytes [](1);

    // В зависимости от типа предложения, формируем данные для голосования
    if (proposeType == ProposeType.A || proposeType == ProposeType.B) {
        // Тип A и B - инвестирование в стартап или добавление инвестиций в стартап в params указываем адрес стартапа и сумму
        (address startup, uint256 amount) = abi.decode(params, (address, uint256));
        targets[0] = startup;
        payable(address(this)).transfer(amount * 1 ether);
        values[0] = amount * 1 ether;
        calldatas[0] = abi.encodeWithSignature("transfer(uint256)", amount * 1 ether);
    } 
    else if (proposeType == ProposeType.C) {
        // Тип C - добавление нового участника в params указываем адрес нового участника 
        address newMember = abi.decode(params, (address));
        targets ;
        values ;
        calldatas ;
        targets[0] = newMember;
        values[0] = 0; 
        calldatas[0] = abi.encodeWithSignature("addMember(address)", newMember);
    } 
    else if (proposeType == ProposeType.D) {
        // Тип D - исключение участника в params указываем адрес участника которого исключаем
        address memberToRemove = abi.decode(params, (address));
        targets ;
        values ;
        calldatas ;
        targets[0] = memberToRemove;
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("removeMember(address)", memberToRemove);
    } 
    else if (proposeType == ProposeType.E) {
        // Тип E - управление системным токеном (изменение параметров токена)
         uint256 newProfiPower = abi.decode(params, (uint256));
            targets[0] = address(this);
            values[0] = newProfiPower;
            calldatas[0] = abi.encodeWithSignature("setProfiPower(uint256)", newProfiPower);
    } 
    else if (proposeType == ProposeType.F) {
        // Тип F - управление wrap-токеном (изменение параметров wrap-токена)
        uint256 newRtkPower = abi.decode(params, (uint256));
            targets[0] = address(this);
            values[0] = newRtkPower;
            calldatas[0] = abi.encodeWithSignature("setRtkPower(uint256)", newRtkPower);
    }

    // Создаем предложение и получаем его ID
    uint256 ID = super.propose(targets, values, calldatas, '');

    // Сохраняем информацию о предложении
    proposeMapping[ID] = ProposeLib({
        proposeID: ID,
        proposeType: proposeType,
        proposer: msg.sender,
        voteStart: uint48(block.timestamp),
        voteEnd: uint48(block.timestamp + _period),
        quorumType: quorumType,
        status: VoteStatus.Active
    });

    // Обновляем голосование по предложению в данных контракта
    voteData[ID].targets = targets;
    voteData[ID].values = values;
    voteData[ID].calldatas = calldatas;

    // Возвращаем ID нового предложения
    return ID;
    }



    ///  Отменить предложение (только инициатор)
    function cancelProposal(uint256 proposalID) external onlyMember {
        ProposeLib storage prop = proposeMapping[proposalID];
        require(msg.sender == prop.proposer, unicode"Только инициатор может отменить");
        prop.status = VoteStatus.Cancelled;

        Vote storage v = voteData[proposalID];
        super.cancel(v.targets, v.values, v.calldatas, keccak256(abi.encodePacked("")));
    }

    // Выполнить предложение, если голосование завершено
    function callExecute(uint256 proposalID) external onlyMember {
    ProposeLib storage prop = proposeMapping[proposalID];
    require(prop.status == VoteStatus.Active, unicode"Голосование не активно");

    // Получаем информацию о голосовании для текущего предложения
    Vote storage votes = voteData[proposalID];
    ProposalVote storage result = _proposalVotes[proposalID];

    // Проверка кворума
    bool approved = _checkQuorum(result, prop.quorumType);
    
    // Если предложение отклонено, меняем статус на "Rejected"
    if (!approved) {
        prop.status = VoteStatus.Rejected;
        return;  // Завершаем выполнение, если кворум не достигнут
    }

    // Если предложение одобрено, меняем статус на "Approved"
    prop.status = VoteStatus.Approved;

    // В зависимости от типа предложения выполняем соответствующее действие
    if (prop.proposeType == ProposeType.A || prop.proposeType == ProposeType.B) {
        // Тип A и B - перевести средства на адрес стартапа
        address startup = abi.decode(votes.calldatas[0], (address));
        uint256 amount = votes.values[0];
        
        // Выполняем перевод
        payable(startup).transfer(amount);
    } 
    else if (prop.proposeType == ProposeType.C) {
        // Тип C - добавить нового участника
        address newMember = abi.decode(votes.calldatas[0], (address));
        
        // Добавляем нового участника в DAO
        addMember(newMember);
    } 
    else if (prop.proposeType == ProposeType.D) {
        // Тип D - удалить участника
        address memberToRemove = abi.decode(votes.calldatas[0], (address));
        
        // Удаляем участника из DAO
        removeMember(memberToRemove);
    } 
    else if (prop.proposeType == ProposeType.E) {
        // Тип E - изменить силу голосов для PROFI
        uint256 newProfiPower = votes.values[0];
        
        // Обновляем силу голосов для PROFI
        setProfiPower(newProfiPower);
    } 
    else if (prop.proposeType == ProposeType.F) {
        // Тип F - изменить силу голосов для RTK
        uint256 newRtkPower = votes.values[0];
        
        // Обновляем силу голосов для RTK
        setRtkPower(newRtkPower);
    }

    }

    ///  Проверка достижения кворума в зависимости от механизма
    function _checkQuorum(ProposalVote storage vote, QuorumMechanism quorumType) internal view returns (bool) {
        uint256 totalVotes = vote.forVotes + vote.againstVotes + vote.abstainVotes;
        if (quorumType == QuorumMechanism.SimpleMajority) {
            return vote.forVotes > vote.againstVotes;
        } else if (quorumType == QuorumMechanism.SuperMajority) {
            return vote.forVotes * 3 > totalVotes * 2; // 2/3 голосов
        } else {
            return vote.forVotes > 0; // Любой весовой голос
        }
    }

    //  Проголосовать за предложение
    function castVote(uint256 proposalId, uint8 support, uint amount) public  returns (uint256) {
        require(!customHasVoted[proposalId][msg.sender], unicode"Уже голосовал");
        customHasVoted[proposalId][msg.sender] = true;

        uint256 weight = _calculateVotingPower(msg.sender, amount);
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

    //  Делегирование RTK-токенов (не DAO-участниками)
    function delegateRTK(address to, uint256 amount) external {
        require(!isMember[msg.sender], unicode"Участники DAO не могут делегировать таким способом");
        require(isMember[to], unicode"Делегировать можно только участнику DAO");

        rtkCoin.transfer(msg.sender, to, amount);
        delegatedRTK[to] += amount;
    }

    //  Делегирование PROFI-токенов между участниками DAO
    function delegateProfiVotes(address to) external onlyMember {
        require(isMember[to], unicode"Только участнику DAO");
        profiCoin.delegate(to);
    }
     

    //  Получить балансы пользователя
    function getBalance() external view returns (uint256 profi, uint256 rtk) {
        return (
            profiCoin.balanceOf(msg.sender),
            rtkCoin.balanceOf(msg.sender)
        );
    }


    // Функция для получения информации о конкретном предложении
    function getProposalInfo(uint256 proposalID) external view returns (Vote memory) {
    return voteData[proposalID]; // Возвращаем информацию о предложении
    }   
}
