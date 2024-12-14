// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Databank is ERC721Enumerable, Ownable {
  uint256 private _tokenIdCounter = 1;

  // Struct to store document metadata
  struct DocumentMetadata {
    string documentHash;      // Hash of the document for verification
    uint256 uploadTimestamp;  // Timestamp of document upload
    string documentURI;       // IPFS or storage URI for the document
    string documentName;      // Name of the document
    string documentType;      // Type/extension of the document
  }

  // Mapping of token ID to document metadata
  mapping(uint256 => DocumentMetadata) public documentMetadata;

  // Mapping to track documents per user
  mapping(address => uint256[]) private userDocuments;

  // Mapping to prevent duplicate document uploads for a user
  mapping(address => mapping(string => bool)) private userDocumentHashes;

  // Events for document-related actions
  event DocumentStored (
    uint256 indexed tokenId,
    address indexed owner,
    string documentHash,
    string documentName
  );

  constructor() Ownable(msg.sender) ERC721("Databank", "DTB") {}

  modifier onlyExistingToken(uint256 tokenId) {
    require(bytes(documentMetadata[tokenId].documentHash).length > 0, "Token does not exist");
    _;
  }

  // Function to store a document as an NFT
  function storeDocument(
    string memory documentHash,
    string memory documentURI,
    string memory documentName,
    string memory documentType
  ) public returns (uint256) {
    // Prevent duplicate document uploads for the same user
    require(!userDocumentHashes[msg.sender][documentHash], "Document already exists");

    // Increment token ID
    uint256 currentTokenId = _tokenIdCounter;

    // Mint NFT to the uploader
    _safeMint(msg.sender, currentTokenId);
    _tokenIdCounter += 1;

    // Store document metadata
    documentMetadata[currentTokenId] = DocumentMetadata({
        documentHash: documentHash,
        uploadTimestamp: block.timestamp,
        documentURI: documentURI,
        documentName: documentName,
        documentType: documentType
    });

    // Track document for the user
    userDocuments[msg.sender].push(currentTokenId);

    // Mark document hash as existing for this user
    userDocumentHashes[msg.sender][documentHash] = true;

    // Emit event
    emit DocumentStored(currentTokenId, msg.sender, documentHash, documentName);

    return currentTokenId;
  }

  // Get documents owned by a user
  function getUserDocuments() public view returns (uint256[] memory) {
    return userDocuments[msg.sender];
  }

  // Get document metadata
  function getDocumentMetadata(uint256 tokenId) public view onlyExistingToken(tokenId) returns (DocumentMetadata memory) {
    require(ownerOf(tokenId) == msg.sender, "You do not own this document");
    return documentMetadata[tokenId];
  }

  // Override tokenURI to return document URI
  function tokenURI(uint256 tokenId) public view virtual override onlyExistingToken(tokenId) returns (string memory) {
    return documentMetadata[tokenId].documentURI;
  }

  // Optional: Allow burning of documents
  function burnDocument(uint256 tokenId) public {
    require(ownerOf(tokenId) == msg.sender, "You can only burn your own documents");
    _burn(tokenId);

    // Remove from user's document list
    uint256[] storage userDocs = userDocuments[msg.sender];
    for (uint256 i = 0; i < userDocs.length; i++) {
      if (userDocs[i] == tokenId) {
        userDocs[i] = userDocs[userDocs.length - 1];
        userDocs.pop();
        break;
      }
    }
  }
}