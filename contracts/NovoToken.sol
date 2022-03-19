// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./INOVO.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";

contract NOVO is INOVO, Initializable, ContextUpgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;

    struct FeeTier {
        uint256 ecoSystemFee;
        uint256 liquidityFee;
        uint256 taxFee;
        uint256 stakingFee;
        uint256 burnFee;
        address ecoSystem;
        address stakingPool;
    }

    struct FeeValues {
        uint256 rAmount;
        uint256 rTransferAmount;
        uint256 rFee;
        uint256 tTransferAmount;
        uint256 tEchoSystem;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tStaking;
        uint256 tBurn;
    }

    struct tFeeValues {
        uint256 tTransferAmount;
        uint256 tEchoSystem;
        uint256 tLiquidity;
        uint256 tFee;
        uint256 tStaking;
        uint256 tBurn;
    }

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcluded;
    mapping (address => bool) private _isBlacklisted;
    mapping (address => bool) private _isExcludedFromAntiWhale;
    mapping (address => uint256) private _accountsTier;

    address[] private _excluded;

    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;
    uint256 private _maxFee;
    uint256 private _targetSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    FeeTier public _defaultFees;
    FeeTier private _previousFees;
    FeeTier private _emptyFees;

    FeeTier[] private feeTiers;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public WBNB;
    address private migration;
    address private _initializerAccount;
    address public _burnAddress;
    address public _treasuryAddress;
    address private _stakingPoolAddress;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled;
    bool public antiWhaleEnabled;

    uint256 public _antiWhaleAmount;
    uint256 public numTokensSellToAddToLiquidity;
    uint256 public numTokensSellToAddToTreasury;
    uint256 public _treasuryStackedAmount;

    bool private _burnStopped;
    bool public canTrade;
    uint256 public launchTime;

    bool private _upgraded;

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event AntiWhaleEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 bnbReceived,
        uint256 tokensIntoLiquidity
    );

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    modifier lockUpgrade {
        require(!_upgraded, "NOVO: Already upgraded");
        _;
        _upgraded = true;
    }

    modifier checkTierIndex(uint256 _index) {
        require(feeTiers.length > _index, "NOVO: Invalid tier index");
        _;
    }

    modifier preventBlacklisted(address _account, string memory errorMsg) {
        require(!_isBlacklisted[_account], errorMsg);
        _;
    }

    modifier isRouter(address _sender) {
        {
            uint32 size;
            assembly {
                size := extcodesize(_sender)
            }
            if(size > 0) {
                uint256 senderTier = _accountsTier[_sender];
                if(senderTier == 0) {
                    IUniswapV2Router02 _routerCheck = IUniswapV2Router02(_sender);
                    try _routerCheck.factory() returns (address factory) {
                        _accountsTier[_sender] = 1;
                    } catch {

                    }
                }
            }
        }

        _;
    }


    function initialize(address _router) public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __NOVO_init_unchained(_router);
    }

    function __NOVO_init_unchained(address _router) internal initializer {
        _name = "Novo Token";
        _symbol = "NOVO";
        _decimals = 9;

        _tTotal = 1000 * 10**6 * 10**9;
        _rTotal = (MAX - (MAX % _tTotal));
        _maxFee = 500;

        swapAndLiquifyEnabled = true;
        antiWhaleEnabled = true;

        _targetSupply = 10 * 10**6 * 10**9;

        _antiWhaleAmount = 5 * 10**6 * 10**9;
        numTokensSellToAddToLiquidity = 5 * 10**5 * 10**9;
        numTokensSellToAddToTreasury = 10**5 * 10**9;

        _burnAddress = 0x000000000000000000000000000000000000dEaD;
        // _treasuryAddress = 0x927A100BCB00553138C6CFA22A4d3A8dbe1156D7;
        _treasuryAddress = 0xCAe485A1E6024413Bc200B4795aFF0a73C6aE6d5;
        // _stakingPoolAddress = 0x38900F0891895C294B039920167Cc9e580bB16ca;
        _stakingPoolAddress = 0x61Ed5DF8E07c5CfDe6846137aD468019aaCbA1f8;
        _initializerAccount = _msgSender();

        _rOwned[_initializerAccount] = _rTotal;

        uniswapV2Router = IUniswapV2Router02(_router);
        WBNB = uniswapV2Router.WETH();
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
        .createPair(address(this), WBNB);

        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        //exclude owner, this contract, burnAddress from anti-whale
        _isExcludedFromAntiWhale[owner()] = true;
        _isExcludedFromAntiWhale[address(this)] = true;
        _isExcludedFromAntiWhale[_burnAddress] = true;
        _isExcludedFromAntiWhale[uniswapV2Pair] = true;

        //exclude burn address from reward
        _isExcluded[_burnAddress] = true;

        __NOVO_tiers_init();

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function __NOVO_tiers_init() internal initializer {
        _defaultFees = _addTier(0, 100, 50, 50, 0, _treasuryAddress, _stakingPoolAddress);
        _addTier(50, 200, 100, 100, 50, _treasuryAddress, _stakingPoolAddress);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "BEP20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "BEP20: decreased allowance below zero"));
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function isExcludedFromAntiWhale(address account) public view returns (bool) {
        return _isExcludedFromAntiWhale[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function reflectionFromTokenInTiers(uint256 tAmount, uint256 _tierIndex, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            FeeValues memory _values = _getValues(tAmount, _tierIndex);
            return _values.rAmount;
        } else {
            FeeValues memory _values = _getValues(tAmount, _tierIndex);
            return _values.rTransferAmount;
        }
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        return reflectionFromTokenInTiers(tAmount, 0, deductTransferFee);
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function excludeFromReward(address account) public onlyOwner() {
        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is already included");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function excludeFromAntiWhale(address account) public onlyOwner() {
        _isExcludedFromAntiWhale[account] = true;
    }

    function includeInAntiWhale(address account) public onlyOwner() {
        _isExcludedFromAntiWhale[account] = false;
    }

    function excludeFromFee(address account) public onlyOwner() {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner() {
        _isExcludedFromFee[account] = false;
    }

    function whitelistAddress(
        address _account,
        uint256 _tierIndex
    )
        public
        onlyOwner()
        checkTierIndex(_tierIndex)
        preventBlacklisted(_account, "NOVO: Selected account is in blacklist")
    {
        require(_account != address(0), "NOVO: Invalid address");
        _accountsTier[_account] = _tierIndex;
    }

    function excludeWhitelistedAddress(address _account) public onlyOwner() {
        require(_account != address(0), "NOVO: Invalid address");
        require(_accountsTier[_account] > 0, "NOVO: Account is not in whitelist");
        _accountsTier[_account] = 0;
    }

    function accountTier(address _account) public view returns (FeeTier memory) {
        return feeTiers[_accountsTier[_account]];
    }

    function isWhitelisted(address _account) public view returns (bool) {
        return _accountsTier[_account] > 0;
    }

    function checkFees(FeeTier memory _tier) internal view returns (FeeTier memory) {
        uint256 _fees = _tier.ecoSystemFee.add(_tier.liquidityFee).add(_tier.taxFee).add(_tier.stakingFee).add(_tier.burnFee);
        require(_fees <= _maxFee, "NOVO: Fees exceeded max limitation");

        return _tier;
    }

    function checkFeesChanged(FeeTier memory _tier, uint256 _oldFee, uint256 _newFee) internal view {
        uint256 _fees = _tier.ecoSystemFee
            .add(_tier.liquidityFee)
            .add(_tier.taxFee)
            .add(_tier.stakingFee)
            .add(_tier.burnFee)
            .sub(_oldFee)
            .add(_newFee);

        require(_fees <= _maxFee, "NOVO: Fees exceeded max limitation");
    }

    function setNumTokensSellToAddToLiquidity(uint256 _amount) external onlyOwner() {
        numTokensSellToAddToLiquidity = _amount.mul(10**9);
    }

    function setNumTokensSellToAddToTreasury(uint256 _amount) external onlyOwner() {
        numTokensSellToAddToTreasury = _amount.mul(10**9);
    }

    function setTreasuryAddress(address _address) external onlyOwner() {
        require(_address != address(0), "NOVO: Address Zero is not allowed");
        _treasuryAddress = _address;
    }

    function setStakingPoolAddress(address _address) external onlyOwner() {
        require(_address != address(0), "NOVO: Address Zero is not allowed");
        _stakingPoolAddress = _address;
    }

    function setEcoSystemFeePercent(uint256 _tierIndex, uint256 _ecoSystemFee) external onlyOwner() checkTierIndex(_tierIndex) {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.ecoSystemFee, _ecoSystemFee);
        feeTiers[_tierIndex].ecoSystemFee = _ecoSystemFee;
        if(_tierIndex == 0) {
            _defaultFees.ecoSystemFee = _ecoSystemFee;
        }
    }

    function setLiquidityFeePercent(uint256 _tierIndex, uint256 _liquidityFee) external onlyOwner() checkTierIndex(_tierIndex) {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.liquidityFee, _liquidityFee);
        feeTiers[_tierIndex].liquidityFee = _liquidityFee;
        if(_tierIndex == 0) {
            _defaultFees.liquidityFee = _liquidityFee;
        }
    }

    function setTaxFeePercent(uint256 _tierIndex, uint256 _taxFee) external onlyOwner() checkTierIndex(_tierIndex) {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.taxFee, _taxFee);
        feeTiers[_tierIndex].taxFee = _taxFee;
        if(_tierIndex == 0) {
            _defaultFees.taxFee = _taxFee;
        }
    }

    function setStakingFeePercent(uint256 _tierIndex, uint256 _stakingFee) external onlyOwner() checkTierIndex(_tierIndex) {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.stakingFee, _stakingFee);
        feeTiers[_tierIndex].stakingFee = _stakingFee;
        if(_tierIndex == 0) {
            _defaultFees.stakingFee = _stakingFee;
        }
    }

    function setBurnFeePercent(uint256 _tierIndex, uint256 _burnFee) external onlyOwner() checkTierIndex(_tierIndex) {
        FeeTier memory tier = feeTiers[_tierIndex];
        checkFeesChanged(tier, tier.burnFee, _burnFee);
        feeTiers[_tierIndex].burnFee = _burnFee;
        if(_tierIndex == 0) {
            _defaultFees.burnFee = _burnFee;
        }
    }

    function setEcoSystemFeeAddress(uint256 _tierIndex, address _ecoSystem) external onlyOwner() checkTierIndex(_tierIndex) {
        require(_ecoSystem != address(0), "NOVO: Address Zero is not allowed");
        feeTiers[_tierIndex].ecoSystem = _ecoSystem;
        if(_tierIndex == 0) {
            _defaultFees.ecoSystem = _ecoSystem;
        }
    }

    function setStakingFeeAddress(uint256 _tierIndex, address _stakingPool) external onlyOwner() checkTierIndex(_tierIndex) {
        require(_stakingPool != address(0), "NOVO: Address Zero is not allowed");
        feeTiers[_tierIndex].stakingPool = _stakingPool;
        if(_tierIndex == 0) {
            _defaultFees.stakingPool = _stakingPool;
        }
    }

    function addTier(
        uint256 _ecoSystemFee,
        uint256 _liquidityFee,
        uint256 _taxFee,
        uint256 _stakingFee,
        uint256 _burnFee,
        address _ecoSystem,
        address _stakingPool
    ) public onlyOwner() {
        _addTier(
            _ecoSystemFee,
            _liquidityFee,
            _taxFee,
            _stakingFee,
            _burnFee,
            _ecoSystem,
            _stakingPool
        );
    }

    function _addTier(
        uint256 _ecoSystemFee,
        uint256 _liquidityFee,
        uint256 _taxFee,
        uint256 _stakingFee,
        uint256 _burnFee,
        address _ecoSystem,
        address _stakingPool
    ) internal returns (FeeTier memory) {
        FeeTier memory _newTier = checkFees(FeeTier(
            _ecoSystemFee,
            _liquidityFee,
            _taxFee,
            _stakingFee,
            _burnFee,
            _ecoSystem,
            _stakingPool
        ));
        excludeFromAntiWhale(_ecoSystem);
        excludeFromAntiWhale(_stakingPool);
        feeTiers.push(_newTier);

        return _newTier;
    }

    function feeTier(uint256 _tierIndex) public view checkTierIndex(_tierIndex) returns (FeeTier memory) {
        return feeTiers[_tierIndex];
    }

    function blacklistAddress(address account) public onlyOwner() {
        _isBlacklisted[account] = true;
        _accountsTier[account] = 0;
    }

    function unBlacklistAddress(address account) public onlyOwner() {
        _isBlacklisted[account] = false;
    }

    function updateRouterAndPair(address _uniswapV2Router,address _uniswapV2Pair) public onlyOwner() {
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        uniswapV2Pair = _uniswapV2Pair;
        WBNB = uniswapV2Router.WETH();
    }

    function setDefaultSettings() external onlyOwner() {
        swapAndLiquifyEnabled = true;
    }

    function setAntiWhalePercent(uint256 percent) external onlyOwner() {
        _antiWhaleAmount = _tTotal.mul(percent).div(
            10**4
        );
    }

    function allowtrading()external onlyOwner() {
        canTrade = true;
        launchTime = block.timestamp;
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner() {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    function setAntiWhaleEnabled(bool _enabled) public onlyOwner() {
        antiWhaleEnabled = _enabled;
        emit AntiWhaleEnabledUpdated(_enabled);
    }

     //to receive BNB from uniswapV2Router when swapping
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount, uint256 _tierIndex) private view returns (FeeValues memory) {
        tFeeValues memory tValues = _getTValues(tAmount, _tierIndex);
        uint256 tTransferFee = tValues.tLiquidity.add(tValues.tEchoSystem).add(tValues.tStaking).add(tValues.tBurn);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tValues.tFee, tTransferFee, _getRate());
        return FeeValues(rAmount, rTransferAmount, rFee, tValues.tTransferAmount, tValues.tEchoSystem, tValues.tLiquidity, tValues.tFee, tValues.tStaking, tValues.tBurn);
    }

    function _getTValues(uint256 tAmount, uint256 _tierIndex) private view returns (tFeeValues memory) {
        FeeTier memory tier = feeTiers[_tierIndex];
        tFeeValues memory tValues = tFeeValues(
            0,
            calculateFee(tAmount, tier.ecoSystemFee),
            calculateFee(tAmount, tier.liquidityFee),
            calculateFee(tAmount, tier.taxFee),
            calculateFee(tAmount, tier.stakingFee),
            calculateFee(tAmount, tier.burnFee)
        );

        tValues.tTransferAmount = tAmount.sub(tValues.tEchoSystem).sub(tValues.tFee).sub(tValues.tLiquidity).sub(tValues.tStaking).sub(tValues.tBurn);
        return tValues;
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tTransferFee, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rTransferFee = tTransferFee.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rTransferFee);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function calculateFee(uint256 _amount, uint256 _fee) private pure returns (uint256) {
        if(_fee == 0) return 0;
        return _amount.mul(_fee).div(
            10**4
        );
    }

    function removeAllFee() private {
        _previousFees = feeTiers[0];
        feeTiers[0] = _emptyFees;
    }

    function restoreAllFee() private {
        feeTiers[0] = _previousFees;
    }

    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }

    function isBlacklisted(address account) public view returns(bool) {
        return _isBlacklisted[account];
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    )
        private
        preventBlacklisted(owner, "NOVO: Owner address is blacklisted")
        preventBlacklisted(spender, "NOVO: Spender address is blacklisted")
    {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    )
        private
        preventBlacklisted(_msgSender(), "NOVO: Address is blacklisted")
        preventBlacklisted(from, "NOVO: From address is blacklisted")
        preventBlacklisted(to, "NOVO: To address is blacklisted")
        isRouter(_msgSender())
    {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (
            from != owner() &&
            to != owner() &&
            !_isExcludedFromAntiWhale[to] &&
            antiWhaleEnabled
        )
            require(balanceOf(to).add(amount) <= _antiWhaleAmount, "Recipient's balance exceeds the antiWhaleAmount.");

        // register snipers to blacklist!
        if (
            from == uniswapV2Pair &&
            to != address(uniswapV2Router) &&
            !_isExcludedFromFee[to] &&
            block.timestamp == launchTime
        ) {
            _isBlacklisted[to] = true;
        }

        // send BNB to the treasury, same as adding liquidity
        bool overMinTokenBalance = _treasuryStackedAmount >= numTokensSellToAddToTreasury;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != uniswapV2Pair
        ) {
            //take treasury
            _takeTreasury(numTokensSellToAddToTreasury);
        }

        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is uniswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));

        overMinTokenBalance = contractTokenBalance >= numTokensSellToAddToLiquidity;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != uniswapV2Pair &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = numTokensSellToAddToLiquidity;
            //add liquidity
            swapAndLiquify(contractTokenBalance);
        }

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        }

        uint256 tierIndex = 0;

        if(takeFee) {
            tierIndex = _accountsTier[from];

            if(_msgSender() != from) {
                tierIndex = _accountsTier[_msgSender()];
            }
        }

        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount, tierIndex, takeFee);
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        // capture the contract's current BNB balance.
        // this is so that we can capture exactly the amount of BNB that the
        // swap creates, and not make the liquidity event include any BNB that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for BNB
        swapTokensForBnb(half);

        // how much BNB did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForBnb(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> wbnb
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of BNB
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address sender, address recipient, uint256 amount, uint256 tierIndex, bool takeFee) private {
        if(!canTrade){
            require(sender == owner()); // only owner allowed to trade or add liquidity
        }

        if(!takeFee)
            removeAllFee();

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount, tierIndex);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount, tierIndex);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount, tierIndex);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount, tierIndex);
        } else {
            _transferStandard(sender, recipient, amount, tierIndex);
        }

        if(!takeFee)
            restoreAllFee();
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount, uint256 tierIndex) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(_values.tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _takeFees(_values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount, uint256 tierIndex) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _takeFees(_values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount, uint256 tierIndex) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(_values.tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _takeFees(_values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount, uint256 tierIndex) private {
        FeeValues memory _values = _getValues(tAmount, tierIndex);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(_values.rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(_values.rTransferAmount);
        _takeFees(_values, tierIndex);
        _reflectFee(_values.rFee, _values.tFee);
        emit Transfer(sender, recipient, _values.tTransferAmount);
    }

    function _takeFees(FeeValues memory values, uint256 tierIndex) private {
        _takeFee(values.tLiquidity, address(this));
        _takeFee(values.tStaking, feeTiers[tierIndex].stakingPool);
        _takeBurn(values.tBurn);

        _takeFee(values.tEchoSystem, address(this));
        _treasuryStackedAmount = _treasuryStackedAmount.add(values.tEchoSystem);
    }

    function _takeFee(uint256 tAmount, address recipient) private {
        if(recipient == address(0)) return;
        if(tAmount == 0) return;

        uint256 currentRate = _getRate();
        uint256 rAmount = tAmount.mul(currentRate);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);
        if(_isExcluded[recipient])
            _tOwned[recipient] = _tOwned[recipient].add(tAmount);
    }
    //

    function _takeTreasury(uint256 _amount) private lockTheSwap {
        uint256 initialBalance = address(this).balance;

        // swap tokens for BNB
        swapTokensForBnb(_amount);

        // how much BNB did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        (bool success,) = payable(_treasuryAddress).call{value: newBalance}('');
        require(success, 'Failed to transfer funds');
        _treasuryStackedAmount = _treasuryStackedAmount.sub(_amount);
    }

    function _takeBurn(uint256 _amount) private {
        if(_burnStopped) return;
        if(_amount == 0) return;

        if(_tOwned[_burnAddress].add(_amount) >= _tTotal.sub(_targetSupply)) {
            _amount = _tTotal.sub(_targetSupply).sub(_tOwned[_burnAddress]);
            _burnStopped = true;
        }

        _tOwned[_burnAddress] = _tOwned[_burnAddress].add(_amount);
    }

    function setMigrationAddress(address _migration) public onlyOwner() {
        migration = _migration;
    }

    function isMigrationStarted() external override view returns (bool) {
        return migration != address(0);
    }

    function migrate(address account, uint256 amount) external override {
        require(migration != address(0), "NOVO: Migration is not started");
        require(_msgSender() == migration, "NOVO: Not Allowed");
        _migrate(account, amount);
    }

    function _migrate(address account, uint256 amount) private {
        require(account != address(0), "BEP20: mint to the zero address");

        _tokenTransfer(_initializerAccount, account, amount, 0, false);
    }

    function feeTiersLength() public view returns (uint) {
        return feeTiers.length;
    }

    function updateBurnAddress(address _newBurnAddress) external onlyOwner() {
        _burnAddress = _newBurnAddress;
    }
}