pragma solidity ^0.8.11;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./INOVO.sol";

contract NovoStaking is Initializable, OwnableUpgradeable {

    struct Stake {
        uint256 amount;
        uint40 startTimestamp;
    }
    
    mapping(address => Stake[]) public allStakes;

    mapping(address => uint256) public stakeCount;

    mapping(address => uint256) public stakerID;

    address[] stakers;

    uint256 public cliff;
    uint256 public vaultAvailableBalance;

    uint256 private constant MAX = ~uint256(0);

    uint40 constant ONE_DAY = 60 * 60 * 24;
    uint40 constant ONE_YEAR = ONE_DAY * 365;

    INOVO public NOVO;

    mapping(address => mapping(uint256 => uint256)) private stackedRewards;
    uint256 private totalStackedRewards;

    event StakeBegan (
        uint256 indexed stakeID,
        address indexed staker,
        uint256 amount,
        uint40 startTimestamp
    );

    event StakeEnded (
        uint256 indexed stakeID,
        address indexed staker,
        uint256 rewardPaid,
        uint256 endTimestamp
    );

    function initialize(address _immutableNOVO) public initializer {
        __Ownable_init_unchained();
        __NovoStaking_init_unchained(_immutableNOVO);
    }

    function __NovoStaking_init_unchained(address _immutableNOVO) internal initializer {
        NOVO = INOVO(_immutableNOVO);
        cliff = 7 * ONE_DAY;
    }

    function setCliff(uint256 _days) external onlyOwner { 
        cliff = _days * ONE_DAY;
    }

    function stake(
        uint256 _amount
    )
        external
    {
        stakeFor(_msgSender(), _amount);
    }

    function stakeFor(
        address _account,
        uint256 _amount
    )
        private
    {
        require(_amount > 0, "NOVO-Stake: Amount cannot be zero");
        
        calculatePartialRewards();

        vaultAvailableBalance += _amount;

        NOVO.transferFrom(
            _account,
            address(this),
            _amount
        );

        uint40 blockTimestamp = uint40(block.timestamp);

        Stake memory newStake = Stake(
            _amount,
            blockTimestamp
        );

        if (stakeCount[_account] == 0) {
            stakers.push(_account);
            stakerID[_account] = stakers.length - 1;
        }

        allStakes[_account].push(newStake);
        stakeCount[_account] = allStakes[_account].length;

        emit StakeBegan(
            stakeCount[_account] - 1,
            _account,
            newStake.amount,
            newStake.startTimestamp
        );
    }

    function unstake(
        uint256 _stakeID,
        uint256 _amount
    )
        external
    {
        unstakeFor(_msgSender(), _stakeID, _amount);
    }

    function unstakeFor(
        address _account,
        uint256 _stakeID,
        uint256 _amount
    )
        private
    {
        require(_stakeID < allStakes[_account].length, "NOVO-Stake: Index is out of range");

        Stake storage selected = allStakes[_account][_stakeID];

        require(
            block.timestamp - selected.startTimestamp >= cliff,
            "NOVO-Stake: Cliff is not reached"
        );
        require(_amount <= available(_account, _stakeID), "NOVO-Stake: Amount exceeds available");

        calculatePartialRewards();

        uint256 reward = currentReward(_account, _stakeID) * _amount / selected.amount;
        
        vaultAvailableBalance -= _amount;
        totalStackedRewards -= reward;
        stackedRewards[_account][_stakeID] -= reward;

        NOVO.transfer(
            _account,
            _amount + reward    
        );

        selected.amount -= _amount;

        if (selected.amount == 0) {
            Stake[] memory stakes = allStakes[_account];
            allStakes[_account][_stakeID] = stakes[stakes.length - 1];
            stackedRewards[_account][_stakeID] = stackedRewards[_account][stakes.length - 1];
            stackedRewards[_account][stakes.length - 1] = 0;
            allStakes[_account].pop();
            stakeCount[_account] -= 1;
        } else {
            _resetTimeStamp(_account, _stakeID);
        }

        if (stakeCount[_account] == 0) {
            uint256 length = stakers.length;
            uint256 index = stakerID[_account];
            address last = stakers[length - 1];
            stakers[index] = last;
            stakerID[_account] = MAX;
            stakerID[last] = index;
            stakers.pop();
        }

        emit StakeEnded(
            _stakeID,
            _account,
            reward,
            block.timestamp
        );
    }

    function stakeInfo(
        address _staker,
        uint256 _stakeID
    )
        external
        view
        returns (
            uint256 amount,
            uint40 startTimestamp,
            uint40 currentTimestamp,
            uint40 lockedDays
        )
    {
        Stake memory selected = allStakes[_staker][_stakeID];

        amount = selected.amount;
        uint40 blockTimeStamp = uint40(block.timestamp);
        lockedDays = (blockTimeStamp - selected.startTimestamp) / ONE_DAY;
        startTimestamp = selected.startTimestamp;
        currentTimestamp = blockTimeStamp;
    }

    function available(
        address _account,
        uint256 _stakeID    
    )
        public
        view
        returns (uint256)
    {
        Stake memory selected = allStakes[_account][_stakeID];
        if (block.timestamp - selected.startTimestamp < cliff) {
            return 0;
        }
        return selected.amount;
    }

    function _stakeRewardableDuration(
        Stake memory _stake
    )
        private
        view
        returns (uint256 duration)
    {
        duration = block.timestamp - _stake.startTimestamp;
    }

    function _getValues() private view returns (uint256, uint256, uint256) {
        uint256 totalTimeStamp;
        uint256 totalBagSize;
        uint256 longestTimeStaked;
        uint256 length = stakers.length;
        
        for (uint256 i = 0 ; i < length ; i ++) {
            address account = stakers[i];
            uint256 count = stakeCount[account];
            for (uint256 j = 0 ; j < count ; j ++) {
                Stake memory selected = allStakes[account][j];
                uint256 duration = _stakeRewardableDuration(selected);

                if (duration > longestTimeStaked)
                    longestTimeStaked = duration;

                totalTimeStamp += duration;
                totalBagSize += selected.amount;
            }
        }

        return (totalTimeStamp, totalBagSize, longestTimeStaked);
    }

    function calculateReward(
        address _account,
        uint256 _stakeID,
        uint256 _amount
    )
        public
        view
        returns (uint256 reward, uint256 longestTimeStaked)
    {
        if (stakeCount[_account] == 0) {
            reward = 0;
            return (reward, 0);
        }
            
        (uint256 totalTimeStamp, uint256 totalBagSize, uint256 longestTS) = _getValues();
        Stake memory selected = allStakes[_account][_stakeID];
        if (_amount == 0)
            _amount = selected.amount;

        uint256 duration = _stakeRewardableDuration(selected);
        uint256 volume = NOVO.balanceOf(address(this));
        uint256 totalRewards = volume - vaultAvailableBalance - totalStackedRewards;
        uint256 rewardForTimeStamp = totalRewards * duration / totalTimeStamp;
        uint256 rewardForBagSize = totalRewards * _amount / totalBagSize;
        reward = (rewardForTimeStamp + rewardForBagSize) / 2;
        longestTimeStaked = longestTS;
    }
    
    function calculatePartialRewards() public {
        uint256 length = stakers.length;
        uint256 total;

        uint256 volume = NOVO.balanceOf(address(this));
        (uint256 totalTimeStamp, uint256 totalBagSize, ) = _getValues();
        uint256 totalRewards = volume - vaultAvailableBalance - totalStackedRewards;


        for (uint256 i = 0 ; i < length ; i ++) {
            address account = stakers[i];
            uint256 count = stakeCount[account];
            for (uint256 j = 0 ; j < count ; j ++) {
                Stake memory selected = allStakes[account][j];

                uint256 duration = _stakeRewardableDuration(selected);
                
                uint256 rewardForTimeStamp = totalRewards * duration / totalTimeStamp;
                uint256 rewardForBagSize = totalRewards * selected.amount / totalBagSize;
                uint256 partialReward = (rewardForTimeStamp + rewardForBagSize) / 2;

                stackedRewards[account][j] += partialReward;
                total += partialReward;
            }
        }
        totalStackedRewards += total;
    }

    function _resetTimeStamp(
        address _account,
        uint256 _stakeID
    )
        private
    {
        Stake storage selected = allStakes[_account][_stakeID];
        selected.startTimestamp = uint40(block.timestamp);
    }

    function claimTokens(address walletaddress) external onlyOwner() {
        NOVO.transfer(walletaddress, NOVO.balanceOf(address(this)));
    }

    function totalStakers() external view returns(uint256) {
        return stakers.length;
    }

    function currentReward(
        address _account,
        uint256 _stakeID
    )
        public
        view
        returns(uint256) 
    {
        return stackedRewards[_account][_stakeID];
    }
}