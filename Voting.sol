// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Импорт необходимых контрактов для реализации Governor стандарта
import {Governor, GovernorVotesQuorumFraction, GovernorVotes, GovernorCountingSimple, IVotes} from "./GovernanceBundle.sol";
import { ProfiCoin, RTKCoin } from "./Tokens.sol";

/**
 * @title MyGovernance
 * @dev Основной контракт системы управления DAO, реализующий стандарт Governor
 * 
 * Контракт предоставляет функционал для:
 * - Создания и управления предложениями
 * - Организации голосований
 * - Управления участниками DAO
 * - Работы с системными токенами
 */
contract MyGovernance is Governor, GovernorVotesQuorumFraction, GovernorCountingSimple {
    
    // Перечисление ролей пользователей в системе
    enum Role { 
        noneUser,   // Неавторизованный пользователь
        userDao,    // Участник DAO (имеет право создавать предложения)
        user        // Обычный пользователь (может только голосовать)
    }
    
    // Типы предложений, которые можно создавать в системе
    enum ProposeType { 
        A, // Инвестирование в новый стартап
        B, // Доп. инвестиции в существующий стартап
        C, // Добавление нового участника
        D, // Исключение участника
        E, // Управление системным токеном
        F  // Управление wrap-токеном
    }

    // Параметры голосования
    uint32 public delay = 0;      // Задержка перед началом голосования (в блоках)
    uint48 public period = 12;    // Длительность голосования (в блоках)
    uint256 public threshold = 0; // Минимальное количество токенов для создания предложения

    // Структура для хранения информации о предложении
    struct ProposeLib {
        uint256 proposeID;    // Уникальный идентификатор предложения
        ProposeType Type;     // Тип предложения
        address proposer;     // Адрес инициатора
        uint48 voteStart;     // Блок начала голосования
        uint48 voteEnd;       // Блок окончания голосования
    }
    
    // Структура для хранения данных голосования
    struct Vote {
        uint256 id;           // ID голосования
        address[] targets;    // Адреса для вызова
        uint256[] values;     // Количество передаваемого ETH
        bytes[] calldatas;    // Данные вызовов
    }
    
    // Структура пользователя системы
    struct User {
        address userAddress;  // Адрес пользователя
        Role role;            // Роль в системе
    }
    
    // Хранилище данных
    mapping (uint256 => Vote) private voteData;          // Данные голосований по ID
    mapping (address => User) private userData;          // Данные пользователей
    mapping(uint256 => ProposalVote) private _proposalVotes; // Результаты голосований
    ProposeLib[] private proposes;                       // Список всех предложений
    
    // Токены системы
    ProfiCoin public profiCoin;  // Системный токен (PROFI)
    RTKCoin public rtkCoin;      // Wrap-токен (RTK)
    
    /**
     * @dev Конструктор контракта
     * @param tom Адрес первого участника DAO
     * @param ben Адрес второго участника DAO
     * @param rick Адрес третьего участника DAO
     * @param jack Адрес обычного пользователя
     * @param _profiCoin Адрес контракта ProfiCoin
     * @param _rtkCoin Адрес контракта RTKCoin
     */
    constructor(
        address tom, 
        address ben, 
        address rick, 
        address jack,
        address _profiCoin,
        address _rtkCoin
    )
        Governor("DAO")  // Название DAO
        GovernorVotes(IVotes(address(ProfiCoin(_profiCoin)))) // Настройка системы голосования
        GovernorVotesQuorumFraction(1) // Установка кворума (1%)
    {
        // Инициализация токенов
        profiCoin = ProfiCoin(_profiCoin);
        rtkCoin = RTKCoin(_rtkCoin);
        
        // Регистрация пользователей
        userData[tom]  = User(tom,  Role.userDao);
        userData[ben]  = User(ben,  Role.userDao);
        userData[rick] = User(rick, Role.userDao);
        userData[jack] = User(jack, Role.user);
        
        // Делегирование голосов участникам
        profiCoin.delegate(tom);
        profiCoin.delegate(ben);
        profiCoin.delegate(rick);
        profiCoin.delegate(jack);
        
        // Создание wrap-токенов для DAO (20 млн с 12 знаками)
        rtkCoin.mint(address(this), 20_000_000 * 10**12);
    }
    
    /**
     * @dev Получение информации о текущем пользователе
     * @return userAddress Адрес пользователя
     * @return role Роль пользователя
     */
    function getUser() external view returns (address userAddress, Role role) {
        return (userData[msg.sender].userAddress, userData[msg.sender].role);
    }
    
    /**
     * @dev Получение списка всех предложений
     * @return Массив структур ProposeLib
     */
    function getProposes() external view returns (ProposeLib[] memory) {
        return proposes;
    }
    
    /**
     * @dev Создание предложения типа A (инвестирование в стартап)
     * @param _delay Задержка перед голосованием
     * @param _period Период голосования
     * @param startup Адрес стартапа
     * @param amount Сумма инвестиций в ETH
     * @return ID созданного предложения
     */
    function setProposeA(uint32 _delay, uint48 _period, address startup, uint amount) 
        external 
        payable  
        returns (uint256) 
    {
        delay = _delay;
        period = _period;

        // Подготовка данных для предложения
        address[] memory targets = new address[](1); 
        uint[] memory values = new uint256[](1); 
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = startup;
        values[0] = amount * 1 ether;
        calldatas[0] = abi.encodeWithSignature("transfer(uint256)", amount);
        
        // Создание предложения
        uint256 ID = super.propose(targets, values, calldatas, '');
        
        // Сохранение данных
        proposes.push(ProposeLib(ID, ProposeType.A, msg.sender, clock(), clock() + period));
        voteData[ID] = Vote(ID, targets, values, calldatas);
        
        return ID;
    }
    
    /**
     * @dev Получение балансов пользователя
     * @return profiBalance Баланс PROFI токенов
     * @return wrapBalance Баланс RTK токенов
     * @return ethBalance Баланс ETH
     */
    function getBalance() external view returns (uint256 profiBalance, uint256 wrapBalance, uint256 ethBalance) {
        return (
            profiCoin.balanceOf(msg.sender),
            rtkCoin.balanceOf(msg.sender),
            msg.sender.balance
        );
    }
    
    /**
     * @dev Получение данных предложения по ID
     * @param proposalID ID предложения
     * @return targets Адреса для вызова
     * @return values Количество ETH для передачи
     * @return calldatas Данные вызовов
     */
    function getPropose(uint256 proposalID) external view returns (
        address[] memory targets, 
        uint256[] memory values, 
        bytes[] memory calldatas
    ) {
        return (
            voteData[proposalID].targets,
            voteData[proposalID].values,
            voteData[proposalID].calldatas
        );
    }
    
    /**
     * @dev Выполнение предложения после успешного голосования
     * @param proposalID ID предложения
     * @return Результат выполнения
     */
    function callExecute(uint256 proposalID) external payable returns (uint256) {
        Vote storage votee = voteData[proposalID];
        return super.execute(votee.targets, votee.values, votee.calldatas, keccak256(abi.encodePacked("")));
    }
    
    /**
     * @dev Подсчет голосов для предложения
     * @param proposalId ID предложения
     * @param account Адрес голосующего
     * @param support Тип голоса (за/против/воздержался)
     * @param totalWeight Общий вес голоса (с учетом токенов)
     * @return Количество учтенных голосов
     * 
     * Примечание: 
     * - 1 голос = 3 PROFI токена
     * - 1 RTK токен = 0.5 голоса (1 RTK = 1 ETH)
     */
    function countVote(uint256 proposalId, address account, uint8 support, uint256 totalWeight) 
        external 
        returns (uint256) 
    {
        ProposalVote storage proposalVote = _proposalVotes[proposalId];
        require(!proposalVote.hasVoted[account], "Already voted");
        
        proposalVote.hasVoted[account] = true;
        
        // Учет голоса в зависимости от типа
        if (support == uint8(VoteType.Against)) {
            proposalVote.againstVotes += totalWeight;
        } else if (support == uint8(VoteType.For)) {
            proposalVote.forVotes += totalWeight;
        } else if (support == uint8(VoteType.Abstain)) {
            proposalVote.abstainVotes += totalWeight;
        } else {
            revert("Invalid vote type");
        }
        
        return totalWeight / 3; // Конвертация веса токенов в голоса
    }
    
    // --- Переопределенные функции Governor ---
    
    /**
     * @dev Получение задержки перед голосованием
     * @return Задержка в блоках
     */
    function votingDelay() public view override returns (uint256) {
        return delay;
    }
    
    /**
     * @dev Получение длительности голосования
     * @return Период в блоках
     */
    function votingPeriod() public view override returns (uint256) {
        return period;
    }
    
    /**
     * @dev Получение минимального порога для создания предложения
     * @return Минимальное количество токенов
     */
    function proposalThreshold() public view override returns (uint256) {
        return threshold;
    }
}