// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title HashSend: A Decentralized Token Transfer & Claim Platform
/// @notice Enables token transfers without needing the recipient’s wallet address, with claim/reclaim functionality, an address book, and dynamic transaction parameters.
contract HashSend {
  // Enum to track transaction status
  enum TxStatus { Pending, Claimed, Reclaimed }

  // Structure to hold transaction details
  struct Transaction {
    address sender;
    address recipient;         // Optional; if not specified, can be address(0)
    uint256 amount;
    string couponCode;         // Passed in from off-chain
    string encryptedPassword;  // Passed in from off-chain (if applicable)
    TxStatus status;
    uint256 timestamp;         // Creation time
  }


  // Mappings
  // Map coupon code to transaction details
  mapping(string => Transaction) public transactions;
  // Map sender address to an array of coupon codes (their transactions)
  mapping(address => string[]) public userTransactions;
  // Map receiver or claimant address to transactions
  mapping(address => string[]) public recipientTransactions;


  // Events for off-chain tracking and transparency
  event TokenSent(
    address indexed sender,
    address indexed recipient,
    uint256 amount,
    string couponCode,
    uint256 timestamp
  );

  event TokenClaimed(
    address indexed claimer,
    string couponCode,
    uint256 amount,
    uint256 timestamp
  );

  event TokenReclaimed(
    address indexed sender,
    string couponCode,
    uint256 amount,
    uint256 timestamp
  );

  // =====================================================
  // WRITE FUNCTIONS
  // =====================================================

  /// @notice Send tokens and create a transaction record.
  /// @param _recipient Optional recipient wallet address (address(0) if not specified).
  /// @param _couponCode Coupon code (generated off-chain).
  /// @param _encryptedPassword Encrypted password (generated off-chain); if not applicable, pass empty string.
  function sendToken(
    address _recipient,
    string calldata _couponCode,
    string calldata _encryptedPassword
  ) external payable {
    require(msg.value > 0, "Amount must be > 0");
    require(bytes(_couponCode).length > 0, "Coupon code required");
    require(transactions[_couponCode].timestamp == 0, "Coupon code already exists");

    _createTransactionRecord(
      msg.value,
      _recipient,
      _couponCode,
      _encryptedPassword
    );
  }

  function _createTransactionRecord(
    uint256 _amount,
    address _recipient,
    string calldata _couponCode,
    string calldata _encryptedPassword
  ) internal {
    if (_recipient != address(0)) {
      recipientTransactions[_recipient].push(_couponCode);
    }

    transactions[_couponCode] = Transaction({
      sender: msg.sender,
      recipient: _recipient,
      amount: _amount,
      couponCode: _couponCode,
      encryptedPassword: _encryptedPassword,
      status: TxStatus.Pending,
      timestamp: block.timestamp
    });

    userTransactions[msg.sender].push(_couponCode);

    emit TokenSent(
      msg.sender,
      _recipient,
      _amount,
      _couponCode,
      block.timestamp
    );
  }

  /// @notice Claim tokens using the coupon code and (if applicable) the password.
  /// @param _couponCode Coupon code associated with the transaction.
  /// @param _password The plaintext password provided by the claimer (if required).
  function claimToken(
    string calldata _couponCode,
    string calldata _password
  ) external {
    Transaction storage txRecord = transactions[_couponCode];
    require(txRecord.timestamp != 0, "Transaction does not exist");
    require(txRecord.status == TxStatus.Pending, "Transaction not pending");

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

    // Transfer to determined recipient
    (bool success, ) = recipient.call{value: txRecord.amount}("");
    require(success, "Transfer failed");

    txRecord.status = TxStatus.Claimed;

    // Add claimant to recipient's transactions
    if (txRecord.recipient == address(0)) {
      txRecord.recipient = msg.sender;
      recipientTransactions[recipient].push(_couponCode);
    }

    emit TokenClaimed(
      recipient,
      _couponCode,
      txRecord.amount,
      block.timestamp
    );
  }

  /// @notice Reclaim tokens if the transaction remains unclaimed.
  /// @param _couponCode Coupon code associated with the transaction.
  function reclaimToken(string calldata _couponCode) external {
    Transaction storage txRecord = transactions[_couponCode];
    require(txRecord.timestamp != 0, "Transaction does not exist");
    require(txRecord.status == TxStatus.Pending, "Transaction not pending");
    require(msg.sender == txRecord.sender, "Only sender can reclaim");

    txRecord.status = TxStatus.Reclaimed;

    // Return tokens to the sender
    (bool success, ) = txRecord.sender.call{value: txRecord.amount}("");
    require(success, "Transfer failed");

    emit TokenReclaimed(
      txRecord.sender,
      _couponCode,
      txRecord.amount,
      block.timestamp
    );
  }

  // =====================================================
  // READ FUNCTIONS
  // =====================================================

  /// @notice Retrieve transaction details using various identifiers.
  /// @param _identifier Could be a coupon code or address.
  /// @return Transaction details.
  function getTransactionDetails(string calldata _identifier) external view returns (Transaction memory) {
    // First check if it's a coupon code
    if (transactions[_identifier].timestamp != 0) {
      return transactions[_identifier];
    }

    // Check if it's an address
    if (bytes(_identifier).length == 42) { // "0x" + 40 hex chars
      address addr = parseAddr(_identifier);
      if (addr != address(0)) {
        // Get all transactions where this address is sender or recipient
        string[] memory senderTxs = userTransactions[addr];
        if (senderTxs.length > 0) {
          return transactions[senderTxs[0]]; // Return the first transaction
        }

        string[] memory receiverTxs = recipientTransactions[addr];
        if (receiverTxs.length > 0) {
          return transactions[receiverTxs[0]]; // Return the first transaction
        }
      }
    }

    revert("Transaction not found");
  }

  /// @notice Helper function to parse address from string
  function parseAddr(string calldata _addrString) internal pure returns (address) {
    bytes memory bytesString = bytes(_addrString);
    uint160 addrValue;

    if (bytesString[0] != '0' || bytesString[1] != 'x') {
      return address(0);
    }

    for (uint i = 2; i < bytesString.length; i++) {
      uint8 digit = uint8(bytesString[i]);

      if (digit >= 48 && digit <= 57) {
        // 0-9
        digit -= 48;
      } else if (digit >= 65 && digit <= 70) {
        // A-F
        digit = digit - 65 + 10;
      } else if (digit >= 97 && digit <= 102) {
        // a-f
        digit = digit - 97 + 10;
      } else {
        return address(0);
      }

      addrValue = addrValue * 16 + digit;
    }

    return address(addrValue);
  }

  /// @notice Retrieve all transactions where the caller is either sender or recipient.
  /// @return Array of Transaction structs.
  function getAllUserTransactions() external view returns (Transaction[] memory) {
    string[] storage senderTxs = userTransactions[msg.sender];
    string[] storage recipientTxs = recipientTransactions[msg.sender];

    uint256 totalCount = senderTxs.length + recipientTxs.length;
    Transaction[] memory allTxs = new Transaction[](totalCount);

    // First add sender transactions
    for (uint256 i = 0; i < senderTxs.length; i++) {
      allTxs[i] = transactions[senderTxs[i]];
    }

    // Then add recipient transactions
    for (uint256 i = 0; i < recipientTxs.length; i++) {
      string memory code = recipientTxs[i];
      bool isDuplicate = false;

      // Check if this transaction is already included (could be both sender and recipient)
      for (uint256 j = 0; j < senderTxs.length; j++) {
        if (keccak256(abi.encodePacked(code)) == keccak256(abi.encodePacked(senderTxs[j]))) {
          isDuplicate = true;
          break;
        }
      }

      if (!isDuplicate) {
        allTxs[senderTxs.length + i] = transactions[code];
      }
    }

    return allTxs;
  }

  /// @notice Retrieve all pending transactions where the caller is the recipient.
  /// @return Array of pending Transaction structs.
  function getPendingClaimsForUser() external view returns (Transaction[] memory) {
    string[] storage recipientTxs = recipientTransactions[msg.sender];

    // First count how many pending transactions there are
    uint256 pendingCount = 0;
    for (uint256 i = 0; i < recipientTxs.length; i++) {
      if (transactions[recipientTxs[i]].status == TxStatus.Pending) {
        pendingCount++;
      }
    }

    // Create array of the right size
    Transaction[] memory pendingTxs = new Transaction[](pendingCount);

    // Fill array with pending transactions
    uint256 currentIndex = 0;
    for (uint256 i = 0; i < recipientTxs.length; i++) {
      Transaction storage txn = transactions[recipientTxs[i]];
      if (txn.status == TxStatus.Pending) {
        pendingTxs[currentIndex] = txn;
        currentIndex++;
      }
    }

    return pendingTxs;
  }

  // Function to check contract balance
  function getContractBalance() external view returns (uint256) {
    return address(this).balance;
  }

  // Allow contract to receive ETH
  receive() external payable {}
}
