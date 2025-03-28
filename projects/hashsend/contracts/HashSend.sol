// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IERC20 {
  function transferFrom(address from, address to, uint256 amount) external returns (bool);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function balanceOf(address account) external view returns (uint256);
}

interface IERC20Detailed is IERC20 {
  function name() external view returns (string memory);
}

/// @title HashSend: A Decentralized Token Transfer & Claim Platform
/// @notice Enables token transfers without needing the recipient’s wallet address, with claim/reclaim functionality, an address book, and dynamic transaction parameters.
contract HashSend {
  // Enum to track transaction status
  enum TxStatus { Pending, Claimed, Reclaimed }

  // Structure to hold transaction details
  struct Transaction {
    address sender;
    address recipient;         // Optional; if not specified, can be address(0)
    address token;
    uint256 amount;
    string couponCode;         // Passed in from off-chain
    string encryptedPassword;  // Passed in from off-chain (if applicable)
    TxStatus status;
    uint256 timestamp;         // Creation time
    uint256 expiration;        // Expiration time for claiming the token
    // Additional parameters that the recipient can modify upon claiming
    string destinationChain;   // e.g., "Ethereum", "Polygon", etc.
    address destinationToken;  // If different from the origin token, a swap can be triggered off-chain
  }

  // Structure to track totals for a given token for each sender
  struct Totals {
    uint256 totalSent;
    uint256 totalClaimed;
  }

  // Structure for an address book entry
  struct WalletEntry {
    address walletAddress;
    string label;
  }

  // Structure for token information returned by getTokensHeld
  struct TokenInfo {
    string name;
    address tokenAddress;
    uint256 balance;
  }

  // Mappings
  // Map coupon code to transaction details
  mapping(string => Transaction) public transactions;
  // Map sender address to an array of coupon codes (their transactions)
  mapping(address => string[]) public userTransactions;
  // Map sender -> token -> Totals (for tracking amounts)
  mapping(address => mapping(address => Totals)) public userTotals;
  // Map user address to their address book (list of wallet entries)
  mapping(address => WalletEntry[]) public addressBook;
  // Map receiver or claimant address to transactions
  mapping(address => string[]) public recipientTransactions;

  // Array and mapping to track unique tokens held by the contract
  address[] public tokensHeld;
  mapping(address => bool) public tokenExists;

  // Events for off-chain tracking and transparency
  event TokenSent(
    address indexed sender,
    address indexed recipient,
    address token,
    uint256 amount,
    string couponCode,
    uint256 timestamp,
    uint256 expiration,
    string destinationChain,
    address destinationToken
  );

  event TokenClaimed(
    address indexed claimer,
    string couponCode,
    address token,
    uint256 amount,
    uint256 timestamp,
    string destinationChain,
    address destinationToken
  );

  event TokenReclaimed(
    address indexed sender,
    string couponCode,
    address token,
    uint256 amount,
    uint256 timestamp
  );

  event WalletAdded(address indexed owner, address wallet, string label);
  event WalletRemoved(address indexed owner, address wallet);

  // =====================================================
  // WRITE FUNCTIONS
  // =====================================================

  /// @notice Send tokens and create a transaction record.
  /// @param _token Address of the ERC20 token.
  /// @param _amount Amount of tokens to send.
  /// @param _recipient Optional recipient wallet address (address(0) if not specified).
  /// @param _couponCode Coupon code (generated off-chain).
  /// @param _encryptedPassword Encrypted password (generated off-chain); if not applicable, pass empty string.
  /// @param _expiration Expiration timestamp (Unix time) for claiming the tokens.
  /// @param _destinationChain Destination chain as a string (pre-filled; recipient can modify on claim).
  /// @param _destinationToken Destination token address (pre-filled; recipient can modify on claim).
  function sendToken(
    address _token,
    uint256 _amount,
    address _recipient,
    string calldata _couponCode,
    string calldata _encryptedPassword,
    uint256 _expiration,
    string calldata _destinationChain,
    address _destinationToken
  ) external {
    require(_amount > 0, "Amount must be > 0");
    require(bytes(_couponCode).length > 0, "Coupon code required");
    require(transactions[_couponCode].timestamp == 0, "Coupon code already exists");

    _transferTokens(_token, _amount);
    _createTransactionRecord(
      _token,
      _amount,
      _recipient,
      _couponCode,
      _encryptedPassword,
      _expiration,
      _destinationChain,
      _destinationToken
    );
  }

  function _transferTokens(address _token, uint256 _amount) internal {
    bool success = IERC20(_token).transferFrom(msg.sender, address(this), _amount);
    require(success, "Token transfer failed");
  }

  function _createTransactionRecord(
    address _token,
    uint256 _amount,
    address _recipient,
    string calldata _couponCode,
    string calldata _encryptedPassword,
    uint256 _expiration,
    string calldata _destinationChain,
    address _destinationToken
  ) internal {
    address destToken = _destinationToken == address(0) ? _token : _destinationToken;

    if (_recipient != address(0)) {
      recipientTransactions[_recipient].push(_couponCode);
    }

    transactions[_couponCode] = Transaction({
      sender: msg.sender,
      recipient: _recipient,
      token: _token,
      amount: _amount,
      couponCode: _couponCode,
      encryptedPassword: _encryptedPassword,
      status: TxStatus.Pending,
      timestamp: block.timestamp,
      expiration: _expiration,
      destinationChain: _destinationChain,
      destinationToken: destToken
    });

    userTransactions[msg.sender].push(_couponCode);
    userTotals[msg.sender][_token].totalSent += _amount;

    if (!tokenExists[_token]) {
      tokensHeld.push(_token);
      tokenExists[_token] = true;
    }

    emit TokenSent(
      msg.sender,
      _recipient,
      _token,
      _amount,
      _couponCode,
      block.timestamp,
      _expiration,
      _destinationChain,
      destToken
    );
  }

  /// @notice Claim tokens using the coupon code and (if applicable) the password.
  /// @param _couponCode Coupon code associated with the transaction.
  /// @param _password The plaintext password provided by the claimer (if required).
  /// @param _newDestinationChain New destination chain (allows recipient to modify pre-filled detail).
  /// @param _newDestinationToken New destination token address (allows recipient to modify pre-filled detail).
  function claimToken(
    string calldata _couponCode,
    string calldata _password,
    string calldata _newDestinationChain,
    address _newDestinationToken
  ) external {
    Transaction storage txRecord = transactions[_couponCode];
    require(txRecord.timestamp != 0, "Transaction does not exist");
    require(txRecord.status == TxStatus.Pending, "Transaction not pending");
    require(block.timestamp <= txRecord.expiration, "Transaction expired");

    if (bytes(txRecord.encryptedPassword).length > 0) {
      require(
        keccak256(abi.encodePacked(_password)) == keccak256(abi.encodePacked(txRecord.encryptedPassword)),
        "Invalid password"
      );
    }

    // Determine recipient - use existing if set, otherwise use caller
    address recipient = txRecord.recipient != address(0)
        ? txRecord.recipient
        : msg.sender;

    // Update chain and token parameters
    txRecord.destinationChain = _newDestinationChain;
    if (_newDestinationToken != address(0)) {
      txRecord.destinationToken = _newDestinationToken;
    }
    txRecord.status = TxStatus.Claimed;

    // Transfer to determined recipient
    require(IERC20(txRecord.token).transfer(recipient, txRecord.amount), "Token transfer failed");

    // Add claimant to recipient's transactions
    if (txRecord.recipient == address(0)) {
      recipientTransactions[recipient].push(_couponCode);
    }

    // Update totals
    userTotals[txRecord.sender][txRecord.token].totalClaimed += txRecord.amount;

    emit TokenClaimed(
      recipient,
      _couponCode,
      txRecord.token,
      txRecord.amount,
      block.timestamp,
      txRecord.destinationChain,
      txRecord.destinationToken
    );
  }

  /// @notice Reclaim tokens if the transaction has expired and remains unclaimed.
  /// @param _couponCode Coupon code associated with the transaction.
  function reclaimToken(string calldata _couponCode) external {
    Transaction storage txRecord = transactions[_couponCode];
    require(txRecord.timestamp != 0, "Transaction does not exist");
    require(txRecord.status == TxStatus.Pending, "Transaction not pending");
    require(block.timestamp > txRecord.expiration, "Transaction not expired");
    require(msg.sender == txRecord.sender, "Only sender can reclaim");

    txRecord.status = TxStatus.Reclaimed;

    // Return tokens to the sender
    require(IERC20(txRecord.token).transfer(txRecord.sender, txRecord.amount), "Token transfer failed");

    emit TokenReclaimed(txRecord.sender, _couponCode, txRecord.token, txRecord.amount, block.timestamp);
  }

  /// @notice Add a wallet to the sender's address book with a label.
  /// @param _walletAddress The wallet address to add.
  /// @param _label A label for the wallet.
  function addWalletToAddressBook(address _walletAddress, string calldata _label) external {
    require(_walletAddress != address(0), "Invalid wallet address");

    WalletEntry[] storage book = addressBook[msg.sender];
    for (uint256 i = 0; i < book.length; i++) {
      require(book[i].walletAddress != _walletAddress, "Wallet already exists");
    }

    book.push(WalletEntry({ walletAddress: _walletAddress, label: _label }));
    emit WalletAdded(msg.sender, _walletAddress, _label);
  }

  /// @notice Remove a wallet from the sender's address book.
  /// @param _walletAddress The wallet address to remove.
  function removeWalletFromAddressBook(address _walletAddress) external {
    WalletEntry[] storage book = addressBook[msg.sender];
    bool found = false;
    uint256 index;
    for (uint256 i = 0; i < book.length; i++) {
      if (book[i].walletAddress == _walletAddress) {
        found = true;
        index = i;
        break;
      }
    }
    require(found, "Wallet not found");

    book[index] = book[book.length - 1];
    book.pop();

    emit WalletRemoved(msg.sender, _walletAddress);
  }

  // =====================================================
  // READ FUNCTIONS
  // =====================================================

  /// @notice Retrieve transaction details using the coupon code.
  /// @param _couponCode Coupon code of the transaction.
  /// @return Transaction details.
  function getTransactionDetailsByCode(string calldata _couponCode) external view returns (Transaction memory) {
    require(transactions[_couponCode].timestamp != 0, "Transaction does not exist");
    return transactions[_couponCode];
  }

  /// @notice Retrieve all transactions initiated by the caller.
  /// @return Array of Transaction structs.
  function getWalletTransactions() external view returns (Transaction[] memory) {
    string[] storage txCodes = userTransactions[msg.sender];
    uint256 count = txCodes.length;
    Transaction[] memory txList = new Transaction[](count);
    for (uint256 i = 0; i < count; i++) {
      txList[i] = transactions[txCodes[i]];
    }
    return txList;
  }

  /// @notice Retrieve all transactions where caller is the recipient
  function getTransactionsWithUserAsRecipient() external view returns (Transaction[] memory) {
    string[] storage txCodes = recipientTransactions[msg.sender];
    Transaction[] memory txList = new Transaction[](txCodes.length);

    for (uint256 i = 0; i < txCodes.length; i++) {
        txList[i] = transactions[txCodes[i]];
    }
    return txList;
  }

  /// @notice Retrieve all claimed transactions where caller is the recipient
  function getUserClaimedTransactions() external view returns (Transaction[] memory) {
    string[] storage txCodes = recipientTransactions[msg.sender];
    uint256 claimedCount;

    // First pass to count claimed
    for (uint256 i = 0; i < txCodes.length; i++) {
        if (transactions[txCodes[i]].status == TxStatus.Claimed) {
            claimedCount++;
        }
    }

    // Second pass to populate array
    Transaction[] memory claimedTx = new Transaction[](claimedCount);
    uint256 currentIndex;
    for (uint256 i = 0; i < txCodes.length; i++) {
        Transaction memory currentTx = transactions[txCodes[i]];
        if (currentTx.status == TxStatus.Claimed) {
            claimedTx[currentIndex] = currentTx;
            currentIndex++;
        }
    }
    return claimedTx;
  }

  /// @notice Retrieve the total amounts sent and claimed by the caller for a given token.
  /// @param _token The token address.
  function getTotals(address _token) external view returns (uint256 totalSent, uint256 totalClaimed) {
    Totals memory totals = userTotals[msg.sender][_token];
    return (totals.totalSent, totals.totalClaimed);
  }

  /// @notice Retrieve the names, addresses, and balances of all tokens the contract is holding.
  /// @return Array of TokenInfo structs.
  function getTokensHeld() external view returns (TokenInfo[] memory) {
    uint256 tokenCount = tokensHeld.length;
    TokenInfo[] memory tokenInfos = new TokenInfo[](tokenCount);
    for (uint256 i = 0; i < tokenCount; i++) {
      address tokenAddr = tokensHeld[i];
      string memory tokenName = "";
      // Attempt to retrieve token name; if the token doesn't implement name(), leave it empty.
      try IERC20Detailed(tokenAddr).name() returns (string memory name) {
        tokenName = name;
      } catch {
        tokenName = "Unknown";
      }
      uint256 balance = IERC20(tokenAddr).balanceOf(address(this));
      tokenInfos[i] = TokenInfo({
        name: tokenName,
        tokenAddress: tokenAddr,
        balance: balance
      });
    }
    return tokenInfos;
  }
}
