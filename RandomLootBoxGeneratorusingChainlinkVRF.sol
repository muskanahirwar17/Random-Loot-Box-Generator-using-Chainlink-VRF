// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RandomLootBoxGenerator is VRFConsumerBaseV2, ERC721URIStorage, Ownable {
    // Chainlink VRF variables - hardcoded for Ethereum Mainnet
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    // NFT Variables
    uint256 private s_tokenCounter;
    uint256 private constant MAX_CHANCE_VALUE = 100;
    uint256 private immutable i_mintFee;

    // Loot Box Rarity
    enum LootBoxRarity {
        COMMON,
        UNCOMMON,
        RARE,
        EPIC,
        LEGENDARY
    }

    // Rarity -> URI Mapping
    mapping(LootBoxRarity => string) private s_rarityToURI;
    
    // VRF Request IDs -> NFT TokenID
    mapping(uint256 => address) private s_requestIdToSender;

    // Events
    event NFTRequested(uint256 indexed requestId, address requester);
    event NFTMinted(LootBoxRarity rarity, address minter, uint256 tokenId);

    constructor() VRFConsumerBaseV2(0x271682DEB8C4E0901D1a1550aD2e64D568E69909) ERC721("Random Loot Box", "RLB") Ownable(msg.sender) {
        // Initialize VRF Coordinator (Ethereum Mainnet)
        i_vrfCoordinator = VRFCoordinatorV2Interface(0x271682DEB8C4E0901D1a1550aD2e64D568E69909);
        
        // Hardcoded values for simplicity - you'll need to update these with your actual values
        i_subscriptionId = 1; // Replace with your actual subscription ID
        i_gasLane = 0x9fe0eebf5e446e3c998ec9bb19951541aee00bb90ea201ae456421a2ded86805; // 150 gwei key hash
        i_callbackGasLimit = 500000; // 500,000 gas
        i_mintFee = 0.01 ether; // 0.01 ETH mint fee
        
        // Set up URI mappings with default values
        s_rarityToURI[LootBoxRarity.COMMON] = "ipfs://QmYaT1YLuqTyPj5YRnMPJtr5uFvDGvLSuJ9W6ELkkSGJ3P/common.json";
        s_rarityToURI[LootBoxRarity.UNCOMMON] = "ipfs://QmYaT1YLuqTyPj5YRnMPJtr5uFvDGvLSuJ9W6ELkkSGJ3P/uncommon.json";
        s_rarityToURI[LootBoxRarity.RARE] = "ipfs://QmYaT1YLuqTyPj5YRnMPJtr5uFvDGvLSuJ9W6ELkkSGJ3P/rare.json";
        s_rarityToURI[LootBoxRarity.EPIC] = "ipfs://QmYaT1YLuqTyPj5YRnMPJtr5uFvDGvLSuJ9W6ELkkSGJ3P/epic.json";
        s_rarityToURI[LootBoxRarity.LEGENDARY] = "ipfs://QmYaT1YLuqTyPj5YRnMPJtr5uFvDGvLSuJ9W6ELkkSGJ3P/legendary.json";
        
        s_tokenCounter = 0;
    }

    /**
     * @notice Request a random loot box by paying the mint fee
     * @dev Uses Chainlink VRF to get random values
     */
    function requestRandomLootBox() public payable {
        require(msg.value >= i_mintFee, "Need to send enough ETH");
        
        // Request randomness from Chainlink VRF
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        
        s_requestIdToSender[requestId] = msg.sender;
        emit NFTRequested(requestId, msg.sender);
    }

    /**
     * @notice Chainlink VRF callback function to fulfill random words and mint NFT
     * @param requestId The ID of the request
     * @param randomWords The array of random values from Chainlink VRF
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        // Get the owner of the NFT
        address nftOwner = s_requestIdToSender[requestId];
        
        // Get current tokenId
        uint256 tokenId = s_tokenCounter;
        
        // Get random number between 1-100 to determine rarity
        uint256 randomValue = randomWords[0] % MAX_CHANCE_VALUE;
        LootBoxRarity rarity = getLootBoxFromRandomValue(randomValue);
        
        // Set the tokenURI based on rarity
        _safeMint(nftOwner, tokenId);
        _setTokenURI(tokenId, s_rarityToURI[rarity]);
        
        // Increment token counter
        s_tokenCounter += 1;
        
        // Emit event
        emit NFTMinted(rarity, nftOwner, tokenId);
    }
    
    /**
     * @notice Determine the loot box rarity based on a random value
     * @param randomValue A random number between 0-99
     * @return The rarity of the loot box
     */
    function getLootBoxFromRandomValue(uint256 randomValue) private pure returns (LootBoxRarity) {
        // Distribution: 
        // Common: 50%
        // Uncommon: 30%
        // Rare: 15%
        // Epic: 4%
        // Legendary: 1%
        
        uint256 cumulativeSum = 0;
        
        if (randomValue >= cumulativeSum && randomValue < cumulativeSum + 50) {
            return LootBoxRarity.COMMON;
        }
        cumulativeSum += 50;
        
        if (randomValue >= cumulativeSum && randomValue < cumulativeSum + 30) {
            return LootBoxRarity.UNCOMMON;
        }
        cumulativeSum += 30;
        
        if (randomValue >= cumulativeSum && randomValue < cumulativeSum + 15) {
            return LootBoxRarity.RARE;
        }
        cumulativeSum += 15;
        
        if (randomValue >= cumulativeSum && randomValue < cumulativeSum + 4) {
            return LootBoxRarity.EPIC;
        }
        
        return LootBoxRarity.LEGENDARY;
    }
    
    /**
     * @notice Allow the contract owner to withdraw funds
     */
    function withdraw() public onlyOwner {
        uint256 amount = address(this).balance;
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Transfer failed");
    }

    // Getter functions
    function getMintFee() public view returns (uint256) {
        return i_mintFee;
    }
    
    function getRarityURI(LootBoxRarity rarity) public view returns (string memory) {
        return s_rarityToURI[rarity];
    }
    
    function getTokenCounter() public view returns (uint256) {
        return s_tokenCounter;
    }
}
