// EARLY CONTINGENCY DRAFT (As of November 2016)

pragma solidity ^0.4.8;
contract Contingency {	
	struct Banker {
		address owner;
		uint balance;
		uint listPosition;
		bytes32 seedHash;
		uint[] bets;
	}
	
	struct Bet {
		address bettor;
		address banker;
		uint amount;
		uint lessThan;
		bytes32 playerSeed;
		//bytes32 bankerSeed;
		uint blockNum;
		uint winnings;
	}
	
	mapping (address => mapping (address => Banker)) bankers;
	mapping (address => mapping (uint => address)) bankerList;
	mapping (address => uint) lastBanker;
	
	mapping (address => mapping (address => uint)) balances;
	
	mapping (address => mapping (uint => Bet)) bets;
	mapping (address => uint) betNum;
	
	uint constant CONST_BANKER_EDGE = 1; // 1%
	uint bankerTimeoutBlocks = 5; // Can claim win if banker is unresponsive in this time
	
	//mapping (address => mapping (uint => Bet)) bets;
	
	mapping (address => uint) minBank;
	
	address owner;

	function Casino() {
		owner = msg.sender;
	}
	
	function test() constant returns (uint) {
	    return bankers[0][bankerList[0][0]].balance;
	}
	
	function sha(bytes32 input) constant returns (bytes32) {
	    return sha256(input);
	}
	
	function balance() constant returns (uint256 balance) {
	    return balanceOf(0, msg.sender);
	}
	
	function balance(address token) constant returns (uint256 balance) {
	    return balanceOf(token, msg.sender);
	}
	
	function balanceOf(address token, address owner) constant returns (uint256 balance) {
	    return balances[token][owner];
	}
	
	function deposit() payable {
	    depositTo(0, msg.value);
	}
	
	function depositTo(address token, uint amount) payable {
	    if (token == 0) {
			amount = msg.value;
	    } else {
	        if (!Token(token).transferFrom(msg.sender, this, amount)) throw;
	    }
	    balances[token][msg.sender] += amount;
	}
	
	function withdraw(uint amount) {
	    withdrawFrom(0, amount);
	}
	
	function withdrawFrom(address token, uint amount) {
	    if (balances[token][msg.sender] < amount) throw;
	    if (token == 0) {
	        if (!msg.sender.send(amount)) throw;
	    } else {
	        if (!Token(token).transfer(msg.sender, amount)) throw;
	    }
	    balances[token][msg.sender] -= amount;
	}
	
	function bank(bytes32 seedHash) returns (bool success) {
	    return bankToken(0,0,seedHash);
	}
	
	function bankToken(address token, uint amount, bytes32 seedHash) returns (bool success) {
		if (token == 0) {
			amount = msg.value;
		} else {
			if (!Token(token).transferFrom(msg.sender, this, amount)) throw;
		}
		if (amount < minBank[token]) throw;
		//TODO: Add to existing bankers?
		Banker banker = bankers[token][msg.sender];
		if (banker.owner == 0) {
			// New banker
			banker.owner = msg.sender;
			banker.listPosition = lastBanker[token];
			banker.bets = new uint[](0);
			bankerList[token][lastBanker[token]++] = msg.sender;
			
		}
		if (banker.seedHash == 0) {
			bankers[token][msg.sender].seedHash = seedHash;
		}
		bankers[token][msg.sender].balance += amount;
		
		return true;
	}
	
	function withdrawFromBank(uint amount) {
		withdrawFromBankAddress(0, msg.sender, amount);
	}
	
	function withdrawFromBankToken(address token, uint amount) {
		withdrawFromBankAddress(token, msg.sender, amount);
	}
	
	function withdrawFromBankAddress(address token, address bankerAddress, uint amount) internal {
		Banker banker = bankers[token][bankerAddress];
		if (amount > banker.balance) throw;
		if (banker.bets.length > 0) throw; // cannot withdraw while bets are in play
		if (banker.balance - amount < minBank[token]) {
			debankAddress(token, bankerAddress);
		} else {
			banker.balance -= amount;
			if (token == 0) {
				if (!bankerAddress.send(amount)) throw;
			} else {
				if (!Token(token).transfer(bankerAddress, amount)) throw;
			}
		}
	}
	
	function debankAddress(address token, address bankerAddress) internal returns (bool success) {
		// Replaces my spot with the banker at the end of the list
		Banker banker = bankers[token][bankerAddress];
		if (banker.owner == 0) throw;
		if (lastBanker[token]-1 != banker.listPosition) {
		   
			bankers[token][bankerList[token][lastBanker[token]-1]].listPosition = banker.listPosition;
			bankerList[token][banker.listPosition] = bankerList[token][lastBanker[token]-1];
		}
		lastBanker[token]--;
		
		if (token == 0) {
			if (!bankerAddress.send(banker.balance)) throw;
		} else {
			if (!Token(token).transfer(bankerAddress, banker.balance)) throw;
		}
		return true;
	}
	
	function randomBanker(address token, bytes32 seed) constant returns (uint128) {
		// Is sha256 hashing needed?
		return (uint128) ((uint(sha256(seed)) & 0xffff) * lastBanker[token]) / 63999;
	}
	
	function bet(uint lessThan, bytes32 seed) returns (uint betID) {
		return betToken(0, 0, lessThan, seed, 0);
	}
	
	function betToken(address token, uint amount, uint lessThan, bytes32 seed, uint houseEdgeAdd) returns (uint betID) {
		if (lessThan > 63999) throw;
		if (token == 0) {
			// Betting ether
			amount = msg.value;
		} else {
		    if (msg.value > 0) throw;
			// Betting a token
			if (!Token(token).transferFrom(msg.sender, this, amount)) throw;
		}
		if (balances[token][msg.sender] < amount) throw;
		
		Banker banker = bankers[token][bankerList[token][randomBanker(token, seed)]];

		if (banker.owner == 0) throw; // NEED TO REENABLE THIS
		
		uint canBeWon;
		for(uint i=0; i<banker.bets.length; i++) {
		    canBeWon += bets[token][banker.bets[i]].winnings;
		}
		uint winnings = calcWinnings(amount, lessThan, CONST_BANKER_EDGE + houseEdgeAdd);
		if (canBeWon + winnings > banker.balance) throw;
		
		
		Bet bet = bets[token][betNum[token]];
		bet.bettor = msg.sender;
		bet.banker = banker.owner;
		bet.amount = amount;
		bet.lessThan = lessThan;
		bet.playerSeed = seed;
		bet.blockNum = block.number;
		bet.winnings = winnings;
		
		//banker.bets.push(betNum[token]);
		
		balances[token][msg.sender] -= amount;
		
		banker.bets[banker.bets.length++] = betNum[token];
		
		return betNum[token]++;
	}
	
	function resolveAndDebank(address token, bytes32 seed) {
		if (!resolveAndSetNewSeed(token, seed, "")) throw;
		if (!debankAddress(token, msg.sender)) throw;
	}
	
	function resolveAndSetNewSeed(address token, bytes32 seed, bytes32 newSeedHash) returns (bool success) {
		Banker banker = bankers[token][msg.sender];
		if (sha256(seed) != banker.seedHash) throw;
		for (uint i=0; i<banker.bets.length; i++) {
			Bet bet = bets[token][banker.bets[i]];
			//bet.bankerSeed = seed;
			if (calcWin(seed, bet.playerSeed, banker.bets[i], bet.lessThan)) {
			    //uint winnings = calcWinnings(bet.amount, bet.lessThan, CONST_BANKER_EDGE);
			    balances[token][bet.bettor] += bet.winnings;
			    banker.balance -= bet.winnings;
			} else {
			    banker.balance += bet.amount;
			}
		}
		banker.bets.length = 0;
		banker.seedHash = newSeedHash;
		return true;
	}
	
	function calcWinnings(uint amount, uint lessThan, uint bankerEdge) constant returns (uint) {
		return amount * 64000 / lessThan * (100 - bankerEdge) / 100;
	}
	
	/*
	function getStatus(address token, uint betID) constant returns (uint) {
		//0 = pending, 1 = win, 2 = loss
		Bet bet = bets[token][betID];
		if (hasTimedout(token, betID)) return 1;
		if (bet.bankerSeed == 0) return 0;
		if (didWin(token, betID)) return 1;
		return 2;
	}
	
	
	function didWin(address token, uint betID) constant returns (bool) {
		Bet bet = bets[token][betID];
		if (bet.bankerSeed == 0 || bet.playerSeed == 0) return false;
		if (calcWin(bet.bankerSeed, bet.playerSeed, betID, bet.lessThan)) {
			return true;
		}
		return false;
	}
	*/
	
	function calcWin(bytes32 bankerSeed, bytes32 playerSeed, uint betNum, uint lessThan) constant returns (bool) {
	    return (hashToInt(sha256(bankerSeed, playerSeed, betNum)) < lessThan);
	}
	
	/*
	function claimWin(uint betID) noEther returns (uint) {
		return claimWinToken(0, betID);
	}
	
	function claimWinToken(address token, uint betID) noEther returns (uint) {
		if (bets[token][betID].bettor != msg.sender) throw;
		if (!didWin(token, betID)) {
			if (!hasTimedout(token, betID)) throw;
			// Banker has not responded in time. Can claim win
		}
		payWinnings(token, betID);
	}
	*/
	
	function hasTimedout(address token, uint betID) returns (bool) {
		if (bets[token][betID].blockNum + bankerTimeoutBlocks < block.number) return false;
		return true;
	}
	
	/*
	function payWinnings(address token, uint betID) internal returns (uint) {
	    Bet bet = bets[token][betID];
		if (token == 0) {
			if (!msg.sender.send(bet.winnings)) throw;
		} else {
			if (!Token(token).transfer(msg.sender, bet.winnings)) throw;
		}
		delete bets[token][betID];
		return bet.winnings;
	}
	*/
	
	function hashToInt(bytes32 hash) constant returns (uint) {
		// Returns a number between 0 - 63999 from a hash
		return uint(hash) & 0xffff;
	}
	
	function setMinBank(address token, uint amount) {
		if (msg.sender != owner) throw;
		minBank[token] = amount;
	}
	
	function removeIfUnderMin(address token, address bankerAddress) {
		// Todo: Need to not allow if bets resolving?
		Banker banker = bankers[token][bankerAddress];
		if (banker.balance < minBank[token]) {
			debankAddress(token, bankerAddress);
		}
	}
	
	function changeOwner(address newOwner) {
		if (msg.sender != owner) throw;
		owner = newOwner;
	}
}

contract Token {

    /// @return total amount of tokens
    function totalSupply() constant returns (uint256 supply) {}

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) constant returns (uint256 balance) {}

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) returns (bool success) {}

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {}

    /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of wei to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) returns (bool success) {}

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {}

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    uint public decimals;
    string public name;
}

/*
contract SimpleEthGame {
	address casinoAddress;
	
	mapping(address => uint) bets;
	
	function bet(uint lessThan, bytes32 seed) {
		if (bets[msg.sender] != 0) throw; // Existing bet
		uint betID = Casino(casinoAddress).bet(lessThan, seed);
		if (betID == 0) throw;
		bets[msg.sender] = betID;
	}
	
	function withdrawWinnings() {
		uint betID = bets[msg.sender];
		uint winnings = Casino(casinoAddress).claimWin(betID);
		if (winnings == 0) throw;
	}
}
*/

contract SimpleGame {
	// A simple game that allows betting with ETH or any Ethereum standard token
	address casinoAddress;
	
	struct Player {
	    uint balance;
	    uint currentBetID;
	    address currentBetToken;
	}
	
	mapping(address => mapping(address => Player)) players;
	
	function GameToken(address casAddress) {
    	casinoAddress = casAddress;
  	}
	
	function bet(address token, uint amount, uint lessThan, bytes32 seed) payable {
	    Player player = players[token][msg.sender];
		if (player.currentBetID != 0) {
			// Existing bet
			throw;
			//if (Casino(casinoAddress).getStatus(bets[msg.sender].token, bets[msg.sender].betID) == 0) {
				//throw; // Bet still pending
			//}
		}
		if (token == 0) {
			amount = msg.value;
		} else {
			if (!Token(token).transferFrom(msg.sender, this, amount)) throw;
		}
		uint betID = Contingency(casinoAddress).betToken(token, amount, lessThan, seed, 0);
		if (betID == 0) throw;
		player.currentBetID = betID;
		player.currentBetToken = token;
	}
	
	function withdraw(address token, uint amount) {
	    Player player = players[token][msg.sender];
	    if (player.balance < amount) throw;
	    if (!msg.sender.send(amount)) throw;
	    player.balance -= amount;
	}
	
	/*
	function claimWin() {
		Bet bet = bets[msg.sender];
		uint winnings = Casino(casinoAddress).claimWinToken(bet.token, bet.betID);
		if (winnings == 0) throw;
		if (bet.token == 0) {
			if (!msg.sender.send(winnings)) throw;
		} else {
			if (!Token(bet.token).transfer(msg.sender, winnings)) throw;
		}
		delete bets[msg.sender];
	}
	*/
}
