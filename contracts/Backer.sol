// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./erc721/Backer721.sol";

import {
    ISuperfluid,
    ISuperToken,
    ISuperApp,
    ISuperAgreement,
    SuperAppDefinitions
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import {
    ISuperTokenFactory
}
from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperTokenFactory.sol";

import {
    IConstantFlowAgreementV1
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import { 
    INativeSuperToken 
} from "./superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/INativeSuperToken.sol"; 

import { 
    NativeSuperTokenProxy 
} from "./superfluid-finance/ethereum-contracts/contracts/tokens/NativeSuperToken.sol";

import {
    SuperAppBase
} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";

//import { Simple777Recipient } from "./erc777/Simple777Recipient.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC777/IERC777Upgradeable.sol";
import { IERC1820RegistryUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC1820RegistryUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC777/IERC777RecipientUpgradeable.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";
import { IUnlock, IPublicLock } from "./unlock/IUnlock.sol";


interface IBackerFactory {
    function addUser(address user) external returns (bool);    
}

contract Backee is IERC777RecipientUpgradeable, SuperAppBase, Initializable, AccessControlEnumerableUpgradeable {
    using SafeMath for uint256;

    ISuperfluid _host;
    IConstantFlowAgreementV1 _cfa;
    ISuperToken public backerToken;
    ISuperToken private _acceptedToken; // accepted token

    IUnlock unlockProtocol;
   
    address[] backers;
    mapping(address => int96) flowRates;
    string public profile;

    bytes32 public constant MANAGER = keccak256("MANAGER_ROLE");
   
    address admin;
    IBackerFactory factory;

    struct Tier {
        address lock;
        int96 flowRate;
        address token;
        uint256 multiplier;
        string name;
        string metadata;
        bool enabled;
    }
    Tier[] public tiers;

    struct Job {
        address lock;
        address member;
    }
    Job[] public toCancel;

    event BackerTierCreated(
        address indexed backee,
        address lock
    );

    event BackerMemberJoined(
        address indexed backee,
        address lock,
        address member,
        int96 flowRate,
        uint date
    );

    event BackerMemberCanceled(
        address indexed backee,
        address lock,
        address member,
        int96 flowRate,
        uint date
    );

    function initialize(
        address _backerToken,
        address owner,
        address parent
    ) public virtual initializer
    {
        require(address(_backerToken) != address(0), "backerToken is zero address");
        __AccessControl_init_unchained();
        __AccessControlEnumerable_init_unchained();
        console.log("before 1820 registry");
        IERC1820RegistryUpgradeable _erc1820 = IERC1820RegistryUpgradeable(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));

        console.log("chainid", block.chainid);
        if ( block.chainid == 137 ) {
            // Polygon
            _host = ISuperfluid(0x3E14dC1b13c488a8d5D310918780c983bD5982E7);
            _cfa = IConstantFlowAgreementV1(0x6EeE6060f715257b970700bc2656De21dEdF074C);
        }
        if ( block.chainid == 80001 ) {
            // Mumbai
            _host = ISuperfluid(0xEB796bdb90fFA0f28255275e16936D25d3418603);
            _cfa = IConstantFlowAgreementV1(0x49e565Ed1bdc17F3d220f72DF0857C26FA83F873);
        }
        if ( block.chainid == 42 ) {
            // Kovan
            _host = ISuperfluid(0xF0d7d1D47109bA426B9D8A3Cde1941327af1eea3);
            _cfa = IConstantFlowAgreementV1(0xECa8056809e7e8db04A8fF6e4E82cD889a46FE2F);
        }
        if ( block.chainid == 4 || block.chainid == 31337 ) {
            // Rinkeby
            _host = ISuperfluid(0xeD5B5b32110c3Ded02a07c8b8e97513FAfb883B6);
            _cfa = IConstantFlowAgreementV1(0xF4C5310E51F6079F601a5fb7120bC72a70b96e2A);
        }

        console.log(address(_host), address(_cfa));

        uint256 configWord =
            SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;
        _host.registerAppByFactory(ISuperApp(address(this)), configWord);

        backerToken = ISuperToken(_backerToken);
        admin = owner;
        factory = IBackerFactory(parent);

        //Access Control
        console.log("before any role granting");
        //_setupRole(DEFAULT_ADMIN_ROLE, address(this));
        console.log("before grant default to admin");
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        console.log("after granting DEFAULT admin role");
        _setupRole(MANAGER, admin);

        unlockProtocol = IUnlock(0xD8C88BE5e8EB88E38E6ff5cE186d764676012B0b); // Rinkeby v9?

        // TODO: change this:
        _acceptedToken = ISuperToken(0x745861AeD1EEe363b4AaA5F1994Be40b1e05Ff90); // Rinkeby fDAIx used by Superfluid

    }

    function acceptedToken() external returns(address) {
        return address(_acceptedToken);
    }

    function createTier(int96 flowRate, address token, uint256 multiplier, string calldata name, string calldata metadata)
        external onlyRole(MANAGER)
        returns (Tier memory)
    {
        uint256 version = unlockProtocol.unlockVersion();
        console.log(version);
        bytes12 salt = bytes12(keccak256(abi.encodePacked(flowRate, token)));
        IPublicLock lock = IPublicLock(unlockProtocol.createLock(315360000, token, 0, 10000000, name, salt));
        lock.addLockManager(msg.sender);
        lock.addKeyGranter(msg.sender);
        lock.setEventHooks(address(this), address(this));
        //lock.setBaseTokenURI("https://api.backer.vip/keys/"); // TODO:
        lock.updateLockSymbol("BADGE"); // TODO: change?
        console.log("lock", address(lock));
        // TODO: config the lock: symbol, image, callbacks, etc. -- need Lock interface
        Tier memory tier = Tier(address(lock), flowRate, token, multiplier, name, metadata, true);
        tiers.push(tier);
        emit BackerTierCreated(address(this), address(lock));
        return tier;
    }

    function getAllTiers() public view returns (Tier[] memory) {
        return tiers;
    }

    function setProfile(string calldata _cid) external onlyRole(MANAGER) {
        profile = _cid;
    }
    function getProfile() public view returns (string memory) {
        return profile;
    }

    /// @dev Gelato resolver for cancelKeys()
    function cancelsPending() external view returns(bool canExec, bytes memory execPayload) {
        canExec = toCancel.length > 0;
        execPayload = abi.encodeWithSelector(this.cancelKeys.selector);
    }
    function cancelKeys() external {
        _cancelKeys();
    }

    function _cancelKeys() internal {
        for (uint256 i = 0; i < toCancel.length; i++) {
            console.log("starting on job with index ", i);
            Job memory job = toCancel[i];
            IPublicLock lock = IPublicLock(job.lock);
            if (lock.getHasValidKey(job.member)) {
                lock.expireAndRefundFor(job.member, 0);
            }
        }
        delete toCancel;
    }

    function _getTierForStream(address sToken, int96 flowRate) internal view returns (Tier memory) {
        Tier memory tier;
        for (uint256 i = 0; i < tiers.length; i++) {
            console.log("starting on tier with index ", i);
            if ( (sToken == tiers[i].token) && (flowRate == tiers[i].flowRate) ) {
                tier = tiers[i];
            }
        }
        return tier;
    }

    function getTierForLock(address lockAddr) public view returns (Tier memory) {
        _getTierForLock(lockAddr);
    }

    function _getTierForLock(address lockAddr) internal view returns (Tier memory) {
        Tier memory tier;
        for (uint256 i = 0; i < tiers.length; i++) {
            console.log("starting on tier with index ", i);
            if ( lockAddr == tiers[i].lock ) {
                tier = tiers[i];
            }
        }
        return tier;
    }

    function _grantKeys(address customer, ISuperToken _superToken, bytes32 _agreementId) internal {
        (,int96 inFlowRate,,) = _cfa.getFlowByID(_superToken, _agreementId);
        flowRates[customer] = inFlowRate;
        Tier memory tier = _getTierForStream(address(_superToken), inFlowRate);
        console.log("tier.lock", tier.lock);
        if ( tier.lock != address(0) ) {
            console.log("tier.lock is not zero");
            IPublicLock lock = IPublicLock(tier.lock);
            console.log("after explicit type conversion of lock");
            address[] memory _recipients = new address[](1);
            uint[] memory _expirationTimestamps = new uint[](1);
            address[] memory _keyManagers = new address[](1);
            _recipients[0] = customer;
            _expirationTimestamps[0] = 2236879077;
            _keyManagers[0] = address(this);
            console.log("b4 grantKeys", _recipients[0], _expirationTimestamps[0], _keyManagers[0]);
            //bool isManager = lock.isLockManager(address(this));
            //bool isGranter = lock.isKeyGranter(address(this));
            //console.log("isLockManager", isManager);
            //console.log("isGranter", isGranter);
            lock.grantKeys(_recipients, _expirationTimestamps, _keyManagers);
            console.log("after grantKeys");
            //console.log( "tokenId", lock.getTokenIdFor(customer) );
            emit BackerMemberJoined(address(this), tier.lock, customer, inFlowRate, block.timestamp);
        } else {
            console.log("tier.lock is the zero address");
        }
    }

    function withdraw(uint256 amount) external onlyRole(MANAGER) {
        // TODO: withdrawal fee to protocol / treasury?
        uint256 balance = _acceptedToken.balanceOf(address(this));
        if ( amount > balance) {
            amount = balance;
        }
        _acceptedToken.transfer(msg.sender, amount);
    }

    function grant(address to, uint256 amount) external onlyRole(MANAGER) {
        uint256 balance = backerToken.balanceOf(address(this));
        if ( amount > balance) {
            amount = balance;
        }
        backerToken.transfer(to, amount);
    }

    function grantRole(bytes32 role, address account) public override onlyRole(DEFAULT_ADMIN_ROLE) {
        factory.addUser(account);
        super.grantRole(role, account);
    }

    /// @dev Unlock Protocol callbacks:
    function onKeyCancel(address operator, address to, uint256 refund) external {
        // TODO: anything?
        console.log("onKeyCancel callback");
        console.log(operator, to, refund);
    }
    function keyPurchasePrice(address from, address recipient, address referrer, bytes calldata data) external view returns (uint minKeyPrice) {
        return type(uint).max;
    }
    function onKeyPurchase(address from, address recipient, address referrer, bytes calldata data, uint minKeyPrice, uint pricePaid) external {
        // TODO:
    }

    /**************************************************************************
     * Backer Token Outflows
     *************************************************************************/
    /// @dev If a new stream is opened, or an existing one is opened
    function _updateOutflow(bytes calldata ctx, address customer, bytes32 agreementId)
        private
        returns (bytes memory newCtx)
    {
      newCtx = ctx;
      (,int96 inFlowRate,,) = _cfa.getFlowByID(_acceptedToken, agreementId);
      (,int96 outFlowRate,,) = _cfa.getFlow(backerToken, address(this), customer);
      if (inFlowRate < 0 ) inFlowRate = -inFlowRate; // Fixes issue when inFlowRate is negative

      Tier memory tier = _getTierForStream(address(_acceptedToken), inFlowRate);
      int96 backerFlowRate = inFlowRate;
      if (tier.multiplier != 0) {
          backerFlowRate = int96(int256( uint256(uint96(inFlowRate)).mul(tier.multiplier).div(100) ));
      }

      if ( (outFlowRate != int96(0)) && (inFlowRate != int96(0)) ){
        // @dev if there already exists an outflow, then update it.
        (newCtx, ) = _host.callAgreementWithContext(
            _cfa,
            abi.encodeWithSelector(
                _cfa.updateFlow.selector,
                backerToken,
                customer,
                backerFlowRate,
                new bytes(0) // placeholder
            ),
            "0x",
            newCtx
        );
      } else if (inFlowRate == int96(0)) {
          // @dev if inFlowRate is zero, delete outflow.
          (newCtx, ) = _host.callAgreementWithContext(
              _cfa,
              abi.encodeWithSelector(
                  _cfa.deleteFlow.selector,
                  backerToken,
                  address(this),
                  customer,
                  new bytes(0) // placeholder
              ),
              "0x",
              newCtx
          );
      } else {
          // @dev If there is no existing outflow, then create new flow to equal inflow
          (newCtx, ) = _host.callAgreementWithContext(
              _cfa,
              abi.encodeWithSelector(
                  _cfa.createFlow.selector,
                  backerToken,
                  customer,
                  backerFlowRate,
                  new bytes(0) // placeholder
              ),
              "0x",
              newCtx
          );
      }
    }
    /**************************************************************************
     * SuperApp callbacks
     *************************************************************************/
    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata /*_agreementData*/,
        bytes calldata ,// _cbdata,
        bytes calldata _ctx
    )
        external override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        address customer = _host.decodeCtx(_ctx).msgSender;
        _grantKeys(customer, _superToken, _agreementId);
        _cancelKeys();
        console.log("b4 _updateOutflow");
        return _updateOutflow(_ctx, customer, _agreementId);
    }

    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata /*_agreementData*/,
        bytes calldata ,//_cbdata,
        bytes calldata _ctx
    )
        external override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        console.log("start afterAgreementUpdated");
        address customer = _host.decodeCtx(_ctx).msgSender;
        _grantKeys(customer, _superToken, _agreementId);
        return _updateOutflow(_ctx, customer, _agreementId);
    }
    function afterAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata _agreementData,
        bytes calldata ,//_cbdata,
        bytes calldata _ctx
    )
        external override
        returns (bytes memory newCtx)
    {
        console.log("start afterAgreementTerminated");
        // According to the app basic law, we should never revert in a termination callback
        if (!_isSameToken(_superToken) || !_isCFAv1(_agreementClass)) return _ctx;
        if (msg.sender != address(_host)) return _ctx;
        (address customer,) = abi.decode(_agreementData, (address, address));
        (,int96 inFlowRate,,) = _cfa.getFlowByID(_superToken, _agreementId);
        console.log("inFlowRate:");
        console.logInt(inFlowRate);
        Tier memory tier = _getTierForStream(address(_superToken), flowRates[customer]);
        if ( tier.lock != address(0) ) {
            console.log("after: found tier");
            //IPublicLock lock = IPublicLock(tier.lock);
            //if (lock.getHasValidKey(customer)) {
            //    lock.expireAndRefundFor(customer, 0);
            //}
            Job memory job = Job(tier.lock, customer);
            toCancel.push(job);
        }
        emit BackerMemberCanceled(address(this), tier.lock, customer, flowRates[customer], block.timestamp);
        return _updateOutflow(_ctx, customer, _agreementId);
    }
    function getNetFlow() public view returns (int96) {
       return _cfa.getNetFlow(_acceptedToken, address(this));
    }
    function _isSameToken(ISuperToken superToken) private view returns (bool) {
        return address(superToken) == address(_acceptedToken);
    }
    function _isCFAv1(address agreementClass) private view returns (bool) {
        return ISuperAgreement(agreementClass).agreementType()
            == keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    }
    modifier onlyHost() {
        require(msg.sender == address(_host), "Backee: support only one host");
        _;
    }
    modifier onlyExpected(ISuperToken superToken, address agreementClass) {
        require(_isSameToken(superToken), "Backee: not accepted token");
        require(_isCFAv1(agreementClass), "Backee: only CFAv1 supported");
        _;
    }

    function tokensReceived(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override {
        require(msg.sender == address(backerToken), "Simple777Recipient: Invalid token");
        // do nothing
    }

}


contract BackerFactory {
    address immutable backeeImplementation;
    address owner;
    address[] public allBackees;
    mapping(address => address[]) userToBackees;
    mapping(address => address) ownerOfBackee;

    ISuperTokenFactory private _superTokenFactory;

    constructor() public {
        _superTokenFactory = ISuperTokenFactory(0xd465e36e607d493cd4CC1e83bea275712BECd5E0); // Rinkeby
        backeeImplementation = address(new Backee());
        owner = msg.sender;
    }

    event BackeeCreated(
        address indexed _owner,
        address _contract
    );

    event BackerTokenCreated(
        address indexed _owner,
        address _contract
    );

    function createBackee(string calldata name, string calldata symbol, uint256 supply) external returns (address) {
        console.log(block.timestamp);
        // step 1: create super token
        INativeSuperToken backerToken = INativeSuperToken(address(new NativeSuperTokenProxy()));
        console.log("backerToken", address(backerToken));
        // step 2: creat backee super app
        address backee = Clones.clone(backeeImplementation);
        console.log("backee", address(backee));
        // step 3: initialize superApp
        Backee(backee).initialize(address(backerToken), msg.sender, address(this));
        console.log("after backee init");
        // step 4: Set the proxy to use the Super Token logic managed by Superfluid Protocol Governance
        _superTokenFactory.initializeCustomSuperToken(address(backerToken));
        console.log("after supertokenfatcory init");
        // step 5: initialize backer token
        backerToken.initialize(
            name,
            symbol,
            supply,
            address(backee)
        );
        console.log("after backerToken init");

        // registry stuff
        allBackees.push(backee);
        userToBackees[msg.sender].push(backee);
        ownerOfBackee[backee] = msg.sender;
        emit BackerTokenCreated(msg.sender, address(backerToken));
        emit BackeeCreated(msg.sender, address(backee));
        return backee;
    }

    // should be called only by backee contract
    function addUser(address user) external returns (bool) {
        userToBackees[user].push(msg.sender);
        return true;
    }

    // returns array of all Backee contract addresses
    function getAllBackees() public view returns (address[] memory){
       return allBackees;
    }

    // returns array of all Backee contract addresses for a specified user address
    function getBackeesForUser(address user) public view returns (address[] memory){
       return userToBackees[user];
    }

}
