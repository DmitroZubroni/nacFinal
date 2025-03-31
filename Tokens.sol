// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ProfiCoin, RTKCoin } from "./Tokens.sol";
import  "./GovernanceBundle.sol";

contract Voting {

    // Контракты токенов
    ProfiCoin public profiToken;
    RTKCoin public rtkToken;    

    uint RTKPower = 2;
    
    // Структура предложения
    struct Proposal {
        uint256 id;             // ID предложения
        address proposer;       // адрес создателя предложения
        uint8 pType;            // тип предложения (0=A, 1=B, 2=C, 3=D, 4=E, 5=F)
        address targetAddress;  // целевой адрес (стартап или участник)
        uint256 amount;         // сумма инвестиций (если требуется)
        uint256 endTime;        // время окончания голосования
        uint256 forVotes;       // суммарное количество голосов "за"
        uint256 againstVotes;   // суммарное количество голосов "против"
        bool executed;          // исполнено ли предложение
        bool canceled;          // отменено ли предложение
        uint8 quorumType;       // тип кворума: 0 = простое большинство, 1 = супербольшинство, 
    }
    
    Proposal[] public proposals; // список предложений

    // нахождение структуры по propsalid
    mapping(uint => Proposal) public proposalsMap;
    
    // Маппинги для отслеживания состояния
    mapping(address => bool) public isMember; 

    mapping(uint256 => mapping(address => bool)) public hasVoted; // отслеживание голосов по каждому предложению

    mapping(address => uint256) public delegatedRTK; // делегированные RTK токены для конкретного адреса
    
    // Модификатор для функций, доступных только участникам DAO
    modifier onlyMember() {
        require(isMember[msg.sender], unicode"Только участники DAO могут выполнять это действие");
        _;
    }
    
    // Конструктор: инициализирует токены и добавляет создателя контракта как первого участника
    constructor(address _profiToken, address _rtkToken, address tom, address ben, address rick) {
        profiToken = ProfiCoin(_profiToken);
        rtkToken = RTKCoin(_rtkToken);
        rtkToken.mint(address(this), 20_000_000);
        _addMember(tom);
        _addMember(ben);
        _addMember(rick);
    }

    // Внутренняя функция добавления участника
    function _addMember(address _member) internal {
        if (!isMember[_member]) {
            isMember[_member] = true;
        }
    }
    
    // функция для приобретения wrap token
    function buyToken(uint amount) external payable {
        require(amount * rtkToken.price() >= msg.value, unicode"Не хватает средств");
        rtkToken.transfer(address(this), msg.sender, amount * 10 ** rtkToken.decimals());
    }
   
    // Расчёт силы голоса участника с учетом вложенных токенов токенов и делегированных RTK
    // 3 PROFI дает 1 голос, 6 RTK дают 1 голос
    function _calculateVotingPower(address _member, uint amount) private view returns (uint256) {
        uint256 profiBalance = amount;
        uint256 rtkBalance = amount + delegatedRTK[_member];
        
        uint256 profiPower = profiBalance / 3;
        uint256 rtkPower = rtkBalance / RTKPower / 3;
        
        return profiPower + rtkPower;
    }

    //проверка достижения кворума
    function checkQuorum(uint256 _proposalId) private view returns (bool) {
    Proposal storage p = proposals[_proposalId];
    uint256 totalVotes = 0;
    if (totalVotes == 0) return false;

    // Кворум "простое большинство"
    if (p.quorumType == 0) {
        return p.forVotes > p.againstVotes;
    } 
    
    // Кворум "супербольшинство (2/3 голосов)"
    else if (p.quorumType == 1) {
         totalVotes = p.forVotes + p.againstVotes;        

        return p.forVotes * 3 >= totalVotes * 2;
    } 

    return true;
}
    
    /*
     Функция создания нового предложения
     _pType: тип предложения (0=A, 1=B, 2=C, 3=D, 4=E, 5=F)
     _targetAddress: адрес (например, адрес стартапа или нового участника)
     _amount: сумма инвестиций 
     _quorumType: тип кворума (0=простое, 1=супер, 2=взвешенное)
     _duration: продолжительность голосования в секундах
    */
    function createProposal(uint8 _pType, address _targetAddress, uint256 _amount, uint8 _quorumType, uint256 _duration) external onlyMember returns (uint256) {
        
        require(_pType <= 5, unicode"Неверный тип предложения");
        
        uint256 proposalId = proposals.length;
        uint256 endTime = block.timestamp + _duration;
        
        proposals.push(Proposal({
            id: proposalId,
            proposer: msg.sender,
            pType: _pType,
            targetAddress: _targetAddress,
            amount: _amount,
            endTime: endTime,
            forVotes: 0,
            againstVotes: 0,
            executed: false,
            canceled: false,
            quorumType: _quorumType
        }));
        
        return proposalId;
    }
    
    // Функция отмены предложения инициатором до завершения голосования
    function cancelProposal(uint256 _proposalId) external onlyMember {
        Proposal storage p = proposals[_proposalId];
        require(msg.sender == p.proposer, unicode"Только инициатор может отменить предложение");
        require(!p.executed, unicode"Предложение уже исполнено");
        require(!p.canceled, unicode"Предложение уже отменено");
        require(block.timestamp < p.endTime, unicode"Голосование уже завершено");
        
        p.canceled = true;
    }

    // Функция делегирования RTK токенов другому участнику DAO
    // Делегированные токены учитываются при расчёте силы голосов
    function delegateRTK(address _to, uint256 _amount) external onlyMember {
        require(isMember[_to], unicode"Делегировать можно только участникам DAO");
        require(rtkToken.transferFrom(msg.sender, address(this), _amount), unicode"Ошибка передачи токенов");
        delegatedRTK[_to] += _amount;
    }
    
    // Функция голосования по предложению
    // _support: true - голос "за", false - голос "против"
    function vote(uint256 _proposalId, bool _support, uint amount) external onlyMember {
        Proposal storage p = proposals[_proposalId];
        require(block.timestamp < p.endTime, unicode"Голосование уже завершено");
        require(!p.canceled, unicode"Предложение отменено");
        require(!hasVoted[_proposalId][msg.sender], unicode"Вы уже проголосовали");
        
        uint256 power = _calculateVotingPower(msg.sender, amount);
        require(power > 0, unicode"У вас нет прав для голосования");
        
        hasVoted[_proposalId][msg.sender] = true;
        if(p.pType == 0 || p.pType == 1 ) {
            profiToken.transferFrom(msg.sender, address(this), amount);
        }

        if (_support) {
            p.forVotes += power;
        
        } else {
            p.againstVotes += power;
        }
        
    }
    
    // Функция исполнения предложения после окончания голосования, если достигнут кворум
    function executeProposal(uint256 _proposalId) external onlyMember {
        Proposal storage p = proposals[_proposalId];
        require(block.timestamp >= p.endTime, unicode"Голосование еще не завершено");
        require(!p.executed, unicode"Предложение уже исполнено");
        require(!p.canceled, unicode"Предложение отменено");
        require(checkQuorum(_proposalId), unicode"Кворум не достигнут");
        
        // Реализация логики исполнения в зависимости от типа предложения
        if (p.pType == 0 || p.pType == 1) {
            // Инвестиционные предложения: здесь должна быть логика инвестирования (placeholder)
        } else if (p.pType == 2) {
            // Добавление нового участника
            _addMember(p.targetAddress);
        } else if (p.pType == 3) {
            // Исключение участника
            isMember[p.targetAddress] = false;
        } else if (p.pType == 4) {
            // Управление системным токеном (ProfiCoin): реализация по требованиям проекта 
        } else if (p.pType == 5) {
            // Управление wrap-токеном (RTKCoin): реализация по требованиям проекта 
        }
        
        p.executed = true;
    } 

    function getBalance() external view returns(uint balanceSystem, uint balanceWrap) {
        if (isMember[msg.sender] == true) {
            balanceSystem = profiToken.balanceOf(msg.sender);
            balanceWrap = 0;
        } else {
            balanceWrap = rtkToken.balanceOf(msg.sender);
            balanceSystem = 0;
        }
    }  
    
    // Геттер для получения силы голоса участника
    function getVotingPower(address _member, uint amount) external view returns (uint256) {
        return _calculateVotingPower(_member, amount);
    }

    //возвращение информации о голосовании
    function getPropsal(uint _proposalId) external view returns(address proposer, uint8 pType, address targetAddress, uint256 amount, uint256 endTime, uint256 forVotes, uint256 againstVotes, uint8 quorumType) {
    Proposal storage p = proposals[_proposalId];
    return(p.proposer, p.pType, p.targetAddress, p.amount, p.endTime, p.forVotes, p.againstVotes, p.quorumType);
    }
    
    // Геттер для общего количества предложений
    function getProposalCount() external view returns (uint256) {
        return proposals.length;
    }
}
