// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Tokens.sol";

contract Voting {
    // Контракты токенов
    ProfiCoin public profiToken;
    RTKCoin public rtkToken;
    
    // Сила голосов: 1 PROFI = 3 голоса, 2 RTK = 1 голос
    uint256 private constant PROFI_VOTE_POWER = 3;
    uint256 private constant RTK_VOTE_POWER = 1;
    
    // Структура участника DAO
    struct Member {
        address memberAddress; // Адрес участника
        bool isActive;        // Активен ли участник
    }
    
    // Структура предложения
    struct Proposal {
        uint256 id;          // ID предложения
        address proposer;     // Автор предложения
        uint8 pType;         // Тип предложения (0-5 = A-F)
        address targetAddress; // Целевой адрес (стартап/участник)
        uint256 amount;      // Сумма инвестиций (если требуется)
        uint256 endTime;     // Время окончания голосования
        uint256 forVotes;    // Голоса "За"
        uint256 againstVotes;// Голоса "Против"
        bool executed;       // Исполнено ли предложение
        bool canceled;       // Отменено ли предложение
        uint8 quorumType;    // Тип кворума (0=простое, 1=супер, 2=взвешенное)
    }
    
    Member[] public members; // Список участников
    Proposal[] public proposals; // Список предложений
    
    // Маппинги для хранения состояния
    mapping(address => bool) public isMember; // Является ли адрес участником
    mapping(uint256 => mapping(address => bool)) public hasVoted; // Голосовал ли участник
    mapping(address => uint256) public delegatedRTK; // Делегированные RTK токены

    constructor(address _profiToken, address _rtkToken) {
        profiToken = ProfiCoin(_profiToken);
        rtkToken = RTKCoin(_rtkToken);
        _addMember(msg.sender); // Добавляем создателя контракта как первого участника
    }

    // Модификатор для проверки участника
    modifier onlyMember() {
        require(isMember[msg.sender], unicode"Только участники DAO могут выполнять это действие");
        _;
    }

    // Внутренняя функция добавления участника
    function _addMember(address _member) internal {
        if (!isMember[_member]) {
            members.push(Member(_member, true));
            isMember[_member] = true;
        }
    }

    // Создание нового предложения
    function createProposal(
        uint8 _pType,
        address _targetAddress,
        uint256 _amount,
        uint8 _quorumType,
        uint256 _duration
    ) external onlyMember returns (uint256) {
        require(_pType <= 5, unicode"Неверный тип предложения");
        
        // Для инвестиционных предложений требуется взвешенное голосование
        if (_pType == 0 || _pType == 1) {
            require(_quorumType == 2, unicode"Инвестиционные предложения требуют взвешенного голосования");
        }

        uint256 proposalId = proposals.length;
        proposals.push(Proposal(
            proposalId,
            msg.sender,
            _pType,
            _targetAddress,
            _amount,
            block.timestamp + _duration,
            0,
            0,
            false,
            false,
            _quorumType
        ));
        return proposalId;
    }

    // Голосование по предложению
    function vote(uint256 _proposalId, bool _support) external onlyMember {
        Proposal storage p = proposals[_proposalId];
        require(block.timestamp < p.endTime, unicode"Голосование уже завершено");
        require(!hasVoted[_proposalId][msg.sender], unicode"Вы уже проголосовали по этому предложению");
        
        uint256 power = _calculateVotingPower(msg.sender);
        require(power > 0, unicode"У вас нет прав для голосования");

        hasVoted[_proposalId][msg.sender] = true;
        
        if (_support) {
            p.forVotes += power;
        } else {
            p.againstVotes += power;
        }
    }

    // Исполнение предложения
    function executeProposal(uint256 _proposalId) external {
        Proposal storage p = proposals[_proposalId];
        require(block.timestamp >= p.endTime, unicode"Голосование еще не завершено");
        require(!p.executed, unicode"Предложение уже исполнено");

        if (_checkQuorum(_proposalId)) {
            // Добавление нового участника (тип C = 2)
            if (p.pType == 2) _addMember(p.targetAddress);
            p.executed = true;
        }
    }

    // Делегирование RTK токенов другому участнику
    function delegateRTK(address _to, uint256 _amount) external {
        require(isMember[_to], unicode"Делегировать можно только участникам DAO");
        require(rtkToken.transferFrom(msg.sender, address(this), _amount), unicode"Ошибка передачи токенов");
        delegatedRTK[_to] += _amount;
    }

    // Расчет силы голоса участника
    function _calculateVotingPower(address _member) private view returns (uint256) {
        uint256 profiPower = profiToken.balanceOf(_member) * PROFI_VOTE_POWER;
        uint256 rtkPower = (rtkToken.balanceOf(_member) + delegatedRTK[_member]) * RTK_VOTE_POWER / 2;
        return profiPower + rtkPower;
    }

    // Проверка достижения кворума
    function _checkQuorum(uint256 _proposalId) private view returns (bool) {
        Proposal storage p = proposals[_proposalId];
        
        if (p.quorumType == 0) {
            // Простое большинство (50%+1)
            return p.forVotes > p.againstVotes;
        } else if (p.quorumType == 1) {
            // Супер большинство (2/3)
            return p.forVotes * 3 > (p.forVotes + p.againstVotes) * 2;
        } else {
            // Взвешенное голосование (30% от общего веса)
            uint256 totalPower = profiToken.totalSupply() * PROFI_VOTE_POWER + 
                                rtkToken.totalSupply() * RTK_VOTE_POWER / 2;
            return p.forVotes * 10 >= totalPower * 3;
        }
    }

    // Получение силы голоса участника
    function getVotingPower(address _member) external view returns (uint256) {
        return _calculateVotingPower(_member);
    }
}