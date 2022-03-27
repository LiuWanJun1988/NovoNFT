// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./Strings.sol";
import "./INOVO.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title Novo NFT
/// @author LiuWanJun
/// @dev Novo NFT logic is implemented and this is the upgradeable
contract NovoNFT is
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using Strings for bytes;
    using Strings for string;
    using Strings for uint256;

    struct Stake {
        string stakerName;
        uint256 principalBalance;
        uint256 bagSizeReward;
        uint256 stakingTimeReward;
        uint80 startTimestamp;
    }

    string baseURI;
    string public baseExtension;
    uint256 public cost;
    uint256 public maxSupply;
    uint256 public maxMintAmount;
    bool public revealed;
    string public notRevealedUri;

    mapping(uint256 => Stake) private mapStakers;
    mapping(uint256 => bool) private mapLockStatus;

    INOVO public novo;

    uint32 public lockDays;

    function initialize(address _novo) public virtual initializer {
        __Ownable_init();
        __Pausable_init();
        __ERC721_init("Novo Certificate of Stake", "NCOS");

        novo = INOVO(_novo);

        baseExtension = ".json";
        cost = 0.05 ether;
        maxSupply = 1000000000;
        maxMintAmount = 20;
        revealed = false;
        lockDays = 7 days;
    }

    // internal
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    // public
    function mint(uint256 _mintAmount) public payable whenNotPaused {
        uint256 supply = totalSupply();
        require(_mintAmount > 0);
        require(_mintAmount <= maxMintAmount);
        require(supply + _mintAmount <= maxSupply);

        if (msg.sender != owner()) {
            require(msg.value >= cost * _mintAmount);
        }

        for (uint256 i = 1; i <= _mintAmount; i++) {
            _safeMint(msg.sender, supply + i);
        }
    }

    function staking(
        uint256 _tokenId,
        uint256 _amount,
        string memory _stakerName
    ) public whenNotPaused {
        require(ownerOf(_tokenId) == msg.sender, "Invalid Token Owner");

        Stake memory newStake = Stake(
            _stakerName,
            _amount,
            0,
            0,
            uint80(block.timestamp)
        );

        mapStakers[_tokenId] = newStake;

        mapLockStatus[_tokenId] = true;
    }

    function unstaking(uint256 _tokenId) public {
        require(ownerOf(_tokenId) == msg.sender, "Invalid Token Owner");
        require(mapStakers[_tokenId].principalBalance > 0, "No staked address");
        uint256 remainReward = mapStakers[_tokenId].bagSizeReward +
            mapStakers[_tokenId].stakingTimeReward;
        if (remainReward > 0) {
            novo.transfer(
                msg.sender,
                mapStakers[_tokenId].bagSizeReward +
                    mapStakers[_tokenId].stakingTimeReward
            );
        }

        mapStakers[_tokenId].principalBalance = 0;
        mapStakers[_tokenId].bagSizeReward = 0;
        mapStakers[_tokenId].stakingTimeReward = 0;
        delete mapStakers[_tokenId];
    }

    function getReflectionAmount() public returns (uint256) {}

    function getAirdropAmount() public returns (uint256) {}

    function getLockedAmountByAddress(address _address)
        public
        view
        returns (uint256)
    {
        uint256 totalLockedAmount = 0;
        uint256[] memory tokenIds = getTokenIds(_address);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalLockedAmount += getLockedAmountByTokenId(tokenIds[i]);
        }

        return totalLockedAmount;
    }

    function getLockedAmountByTokenId(uint256 _tokenId)
        public
        view
        returns (uint256)
    {
        require(isLocked(_tokenId) == true, "No locked");
        return
            mapStakers[_tokenId].principalBalance +
            mapStakers[_tokenId].bagSizeReward +
            mapStakers[_tokenId].stakingTimeReward;
    }

    function getTokenIds(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory _tokensOfOwner = new uint256[](balanceOf(_owner));
        uint256 i;

        for (i = 0; i < balanceOf(_owner); i++) {
            _tokensOfOwner[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return (_tokensOfOwner);
    }

    function addBagSizeReward(uint256 tokenId, uint256 _amount) internal {
        mapStakers[tokenId].bagSizeReward += _amount;
    }

    function addStakingTimeReward(uint256 tokenId, uint256 _amount) internal {
        mapStakers[tokenId].stakingTimeReward += _amount;
    }

    function isLocked(uint256 _tokenId) public view returns (bool) {
        return mapLockStatus[_tokenId];
    }

    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (revealed == false) {
            return notRevealedUri;
        }

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        tokenId.toString(),
                        baseExtension
                    )
                )
                : "";
    }

    //only owner
    function reveal() public onlyOwner {
        revealed = true;
    }

    function setCost(uint256 _newCost) public onlyOwner {
        cost = _newCost;
    }

    function setmaxMintAmount(uint256 _newmaxMintAmount) public onlyOwner {
        maxMintAmount = _newmaxMintAmount;
    }

    function setNotRevealedURI(string memory _notRevealedURI) public onlyOwner {
        notRevealedUri = _notRevealedURI;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function setLockDays(uint32 _lockDays) public onlyOwner {
        lockDays = _lockDays;
    }

    function setBaseExtension(string memory _newBaseExtension)
        public
        onlyOwner
    {
        baseExtension = _newBaseExtension;
    }

    /**
     * @dev enables owner to pause / unpause minting
     * @param _bPaused the flag to pause / unpause
     */
    function setPaused(bool _bPaused) external onlyOwner {
        if (_bPaused) _pause();
        else _unpause();
    }
}
