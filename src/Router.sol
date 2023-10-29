pragma solidity 0.8.17;

// SPDX-License-Identifier: AGPL-3.0-only

import "interface/IPair.sol";
import "interface/IWETH.sol";
import "interface/IFactory.sol";
import "interface/IERC20Permit.sol";
import "interface/IGauge.sol";
import "interface/IERC20.sol";
import "interface/IsDYSON.sol";
import "./lib/SqrtMath.sol";
import "./lib/TransferHelper.sol";

/// @title Router contract for all Pair contracts
/// @notice Users are expected to swap, deposit and withdraw via this contract
/// @dev IMPORTANT: Fund stuck or send to this contract is free for grab as `pair` param
/// in each swap functions is passed in and not validated so everyone can implement their
/// own `pair` contract and transfer the fund away.
contract Router {
    using SqrtMath for *;
    using TransferHelper for address;

    uint private constant MAX_FEE_RATIO = 2**64;
    address public immutable WETH;
    address public immutable DYSON_FACTORY;
    address public immutable sDYSON;
    address public immutable DYSON;
    bytes32 public immutable CODE_HASH;

    address public owner;

    event TransferOwnership(address newOwner);

    constructor(address _WETH, address _owner, address _factory, address _sDYSON, address _DYSON) {
        require(_owner != address(0), "owner cannot be zero");
        require(_WETH != address(0), "invalid WETH");
        WETH = _WETH;
        owner = _owner;
        DYSON_FACTORY = _factory;
        sDYSON = _sDYSON;
        DYSON = _DYSON;
        CODE_HASH = IFactory(DYSON_FACTORY).getInitCodeHash();
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "forbidden");
        _;
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'identical addresses');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'zero address');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, bytes32 initCodeHash, address tokenA, address tokenB, uint id) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1, id)), //salt
                initCodeHash
            )))));
    }

    function transferOwnership(address _owner) external onlyOwner {
        require(_owner != address(0), "owner cannot be zero");
        owner = _owner;

        emit TransferOwnership(_owner);
    }

    /// @notice Allow another address to transfer token from this contract
    /// @param tokenAddress Address of token to approve
    /// @param contractAddress Address to grant allowance
    /// @param enable True to enable allowance. False otherwise.
    function rely(address tokenAddress, address contractAddress, bool enable) onlyOwner external {
        tokenAddress.safeApprove(contractAddress, enable ? type(uint).max : 0);
    }

    /// @notice rescue token stucked in this contract
    /// @param tokenAddress Address of token to be rescued
    /// @param to Address that will receive token
    /// @param amount Amount of token to be rescued
    function rescueERC20(address tokenAddress, address to, uint256 amount) onlyOwner external {
        tokenAddress.safeTransfer(to, amount);
    }

    /// @notice This contract can only receive ETH coming from WETH contract,
    /// i.e., when it withdraws from WETH
    receive() external payable {
        require(msg.sender == WETH);
    }

    function _swap(address tokenIn, address tokenOut, uint index, address to, uint input, uint minOutput) internal returns (uint output) {
        address pair = pairFor(DYSON_FACTORY, CODE_HASH, tokenIn, tokenOut, index);
        (address token0,) = sortTokens(tokenIn, tokenOut);
        if(tokenIn == token0)
            output = IPair(pair).swap0in(to, input, minOutput);
        else
            output = IPair(pair).swap1in(to, input, minOutput);
    }

    function unwrapAndSendETH(address to, uint amount) internal {
        IWETH(WETH).withdraw(amount);
        to.safeTransferETH(amount);
    }

    /// @notice Swap tokenIn for tokenOut
    /// @param tokenIn Address of spent token
    /// @param tokenOut Address of received token
    /// @param index Number of pair instance
    /// @param to Address that will receive tokenOut
    /// @param input Amount of tokenIn to swap
    /// @param minOutput Minimum of tokenOut expected to receive
    /// @return output Amount of tokenOut received
    function swap(address tokenIn, address tokenOut, uint index, address to, uint input, uint minOutput) external returns (uint output) {
        tokenIn.safeTransferFrom(msg.sender, address(this), input);
        output = _swap(tokenIn, tokenOut, index, to, input, minOutput);
    }

    /// @notice Swap ETH for tokenOut
    /// @param tokenOut Address of received token
    /// @param index Number of pair instance
    /// @param to Address that will receive tokenOut
    /// @param minOutput Minimum of token1 expected to receive
    /// @return output Amount of tokenOut received
    function swapETHIn(address tokenOut, uint index, address to, uint minOutput) external payable returns (uint output) {
        IWETH(WETH).deposit{value: msg.value}();
        return _swap(WETH, tokenOut, index, to, msg.value, minOutput);
    }

    /// @notice Swap tokenIn for ETH
    /// @param tokenIn Address of spent token
    /// @param index Number of pair instance
    /// @param to Address that will receive ETH
    /// @param input Amount of tokenIn to swap
    /// @param minOutput Minimum of ETH expected to receive
    /// @return output Amount of ETH received
    function swapETHOut(address tokenIn, uint index, address to, uint input, uint minOutput) external returns (uint output) {
        tokenIn.safeTransferFrom(msg.sender, address(this), input);
        output = _swap(tokenIn, WETH, index, address(this), input, minOutput);
        unwrapAndSendETH(to, output);
    }

    /// @notice Swap tokenIn for tokenOut with multiple hops
    /// @param tokens Array of swapping tokens
    /// @param indexes Array of pair instance
    /// @param to Address that will receive tokenOut
    /// @param input Amount of tokenIn to swap
    /// @param minOutput Minimum of tokenOut expected to receive
    /// @return output Amount of tokenOut received
    function swapWithMultiHops(address[] calldata tokens, uint[] calldata indexes, address to, uint input, uint minOutput) external returns (uint output) {
        unchecked {
        uint indexesLength = indexes.length;
        require(indexesLength > 0 && tokens.length == indexesLength + 1, "invalid input array length");
        tokens[0].safeTransferFrom(msg.sender, address(this), input);
        uint nextInputAmount = input;
        uint i = 1;
        for(;i < indexesLength; ++i)
            nextInputAmount = _swap(tokens[i-1], tokens[i], indexes[i-1], address(this), nextInputAmount, 0);
        output = _swap(tokens[i-1], tokens[i], indexes[i-1], to, nextInputAmount, minOutput);
        }
    }

    /// @notice Swap ETH for tokenOut with multiple hops
    /// tokens[0] must be WETH
    /// @param tokens Array of swapping tokens
    /// @param indexes Array of pair instance
    /// @param to Address that will receive tokenOut
    /// @param minOutput Minimum of tokenOut expected to receive
    /// @return output Amount of tokenOut received
    function swapETHInWithMultiHops(address[] calldata tokens, uint[] calldata indexes, address to, uint minOutput) external payable returns (uint output) {
        unchecked {
        uint indexesLength = indexes.length;
        require(indexesLength > 0 && tokens.length == indexesLength + 1, "invalid input array length");
        require(tokens[0] == WETH, "first token must be WETH");
        IWETH(WETH).deposit{value: msg.value}();
        uint nextInputAmount = msg.value;
        uint i = 1;
        for(;i < indexesLength; ++i)
            nextInputAmount = _swap(tokens[i-1], tokens[i], indexes[i-1], address(this), nextInputAmount, 0);
        output = _swap(tokens[i-1], tokens[i], indexes[i-1], to, nextInputAmount, minOutput);
        }
    }

    /// @notice Swap tokenIn for ETH with multiple hops
    /// tokens[tokens.length - 1] must be WETH
    /// @param tokens Array of swapping tokens
    /// @param indexes Array of pair instance
    /// @param to Address that will receive ETH
    /// @param input Amount of tokenIn to swap
    /// @param minOutput Minimum of ETH expected to receive
    /// @return output Amount of ETH received
    function swapETHOutWithMultiHops(address[] calldata tokens, uint[] calldata indexes, address to, uint input, uint minOutput) external returns (uint output) {
        unchecked {
        uint indexesLength = indexes.length;
        require(indexesLength > 0 && tokens.length == indexesLength + 1, "invalid input array length");
        require(tokens[indexesLength] == WETH, "last token must be WETH");
        tokens[0].safeTransferFrom(msg.sender, address(this), input);
        uint nextInputAmount = input;
        uint i = 1;
        for(;i < indexesLength; ++i)
            nextInputAmount = _swap(tokens[i-1], tokens[i], indexes[i-1], address(this), nextInputAmount, 0);
        output = _swap(tokens[i-1], tokens[i], indexes[i-1], address(this), nextInputAmount, minOutput);
        unwrapAndSendETH(to, output);
        }
    }

    function _deposit(address tokenIn, address tokenOut, uint index, address to, uint input, uint minOutput, uint time) internal returns (uint output) {
        address pair = pairFor(DYSON_FACTORY, CODE_HASH, tokenIn, tokenOut, index);
        (address token0,) = sortTokens(tokenIn, tokenOut);
        if(tokenIn == token0)
            output = IPair(pair).deposit0(to, input, minOutput, time);
        else
            output = IPair(pair).deposit1(to, input, minOutput, time);
    }

    /// @notice Deposit tokenIn
    /// @param tokenIn Address of spent token
    /// @param tokenOut Address of received token
    /// @param index Number of pair instance
    /// @param to Address that will receive Pair note
    /// @param input Amount of tokenIn to deposit
    /// @param minOutput Minimum amount of tokenOut expected to receive if the swap is perfromed
    /// @param time Lock time
    /// @return output Amount of tokenOut received if the swap is performed
    function deposit(address tokenIn, address tokenOut, uint index, address to, uint input, uint minOutput, uint time) external returns (uint output) {
        tokenIn.safeTransferFrom(msg.sender, address(this), input);
        output = _deposit(tokenIn, tokenOut, index, to, input, minOutput, time);
    }

    /// @notice Deposit ETH
    /// @param tokenOut Address of received token
    /// @param index Number of pair instance
    /// @param to Address that will receive Pair note
    /// @param minOutput Minimum amount of tokenOut expected to receive if the swap is perfromed
    /// @param time Lock time
    /// @return output Amount of tokenOut received if the swap is performed
    function depositETH(address tokenOut, uint index, address to, uint minOutput, uint time) external payable returns (uint output) {
        IWETH(WETH).deposit{value: msg.value}();
        return _deposit(WETH, tokenOut, index, to, msg.value, minOutput, time);
    }

    /// @notice Withdrw Pair note.
    /// @param pair `Pair` contract address
    /// @param index Index of the note to withdraw
    /// @param to Address that will receive either token0 or token1
    /// @return token0Amt Amount of token0 withdrawn
    /// @return token1Amt Amount of token1 withdrawn
    function withdraw(address pair, uint index, address to) external returns (uint token0Amt, uint token1Amt) {
        return IPair(pair).withdrawFrom(msg.sender, index, to);
    }

    /// @notice Withdraw multiple Pair notes.
    /// User who call this function must set approval for all position of each pair in advance
    /// @param pairs array of `Pair` contract addresses
    /// @param indexes array of index of the note to withdraw
    /// @param tos array of address that will receive either token0 or token1
    /// @return token0Amounts array of amount of token0 withdrawn
    /// @return token1Amounts array of amount of token1 withdrawn
    function withdrawMultiPositions(address[] calldata pairs, uint[] calldata indexes, address[] calldata tos) external returns (uint[] memory token0Amounts, uint[] memory token1Amounts) {
        uint pairLength = pairs.length;
        require(pairLength == indexes.length && pairLength == tos.length, "invalid input array length");
        uint[] memory _token0Amounts = new uint[](pairLength);
        uint[] memory _token1Amounts = new uint[](pairLength);
        unchecked {
            for (uint i = 0; i < pairLength; ++i) {
                (uint token0Amount, uint token1Amount) = IPair(pairs[i]).withdrawFrom(msg.sender, indexes[i], tos[i]);
                _token0Amounts[i] = token0Amount;
                _token1Amounts[i] = token1Amount;
            }
        }
        (token0Amounts, token1Amounts) = (_token0Amounts, _token1Amounts);
    }

    /// @notice Withdrw Pair note and if either token0 or token1 withdrawn is WETH, withdraw from WETH and send ETH to receiver.
    /// User who signs the withdraw signature must be the one who calls this function
    /// @param pair `Pair` contract address
    /// @param index Index of the note to withdraw
    /// @param to Address that will receive either token0 or token1
    /// @return token0Amt Amount of token0 withdrawn
    /// @return token1Amt Amount of token1 withdrawn
    function withdrawETH(address pair, uint index, address to) external returns (uint token0Amt, uint token1Amt) {
        (token0Amt, token1Amt) = IPair(pair).withdrawFrom(msg.sender, index, address(this));
        address token0 = IPair(pair).token0();
        address token = token0Amt > 0 ? token0 : IPair(pair).token1();
        uint amount = token0Amt > 0 ? token0Amt : token1Amt;
        if (token == WETH)
            unwrapAndSendETH(to, amount);
        else
            token.safeTransfer(to, amount);
    }

    /// @notice Deposit sDYSON to gauge
    /// @param gauge `Gauge` contract address
    /// @param amount Amount of sDYSON to deposit
    /// @param to Address that owns the position of this deposit
    function depositToGauge(address gauge, uint amount, address to) external {
        require(gauge != address(0), "invalid gauge");
        require(amount > 0, "invalid amount");
        sDYSON.safeTransferFrom(msg.sender, address(this), amount);
        IGauge(gauge).deposit(amount, to);
    }

    /// @notice Stake DYSON to sDYSON
    /// @param to Address that owns the position of this stake
    /// @param amount Amount of DYSON to stake
    /// @param lockDuration Lock duration
    function stakeDyson(address to, uint amount, uint lockDuration) external returns (uint sDYSONAmount) {
        require(amount > 0, "invalid amount");
        DYSON.safeTransferFrom(msg.sender, address(this), amount);
        sDYSONAmount = IsDYSON(sDYSON).stake(to, amount, lockDuration);
    }

    /// @notice Permits this contract to spend a given token from msg.sender
    /// The owner is always msg.sender and the spender is always address(this).
    /// @param token The address of the token spent
    /// @param value The amount that can be spent of token
    /// @param deadline A timestamp, the current blocktime must be less than or equal to this timestamp
    /// @param v Must produce valid secp256k1 signature from the holder along with r and s
    /// @param r Must produce valid secp256k1 signature from the holder along with v and s
    /// @param s Must produce valid secp256k1 signature from the holder along with v and r
    function selfPermit(
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    /// @notice Set approval for all position of a pair
    /// User who signs the approval signature must be the one who calls this function
    /// @param pair `Pair` contract address
    /// @param approved True to approve, false to revoke
    /// @param deadline Deadline when the signature expires
    /// @param sig Signature
    function setApprovalForAllWithSig(address pair, bool approved, uint deadline, bytes calldata sig) public {
		IPair(pair).setApprovalForAllWithSig(msg.sender, address(this), approved, deadline, sig);
    }

    /// @notice Multi delegatecall without supporting payable
    /// @param data Array of bytes of function calldata to be delegatecalled
    function multicall(bytes[] calldata data) public returns (bytes[] memory results) {
        uint dataLength = data.length;
        results = new bytes[](dataLength);
        for (uint256 i = 0; i < dataLength; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }

    /// @notice Calculate the price of token1 in token0
    /// Formula:
    /// amount1 = amount0 * reserve1 * sqrt(1-fee0) / reserve0 / sqrt(1-fee1)
    /// which can be transformed to:
    /// amount1 = sqrt( amount0**2 * (1-fee0) / (1-fee1) ) * reserve1 / reserve0
    /// @param pair `Pair` contract address
    /// @param token0Amt Amount of token0
    /// @return token1Amt Amount of token1
    function fairPrice(address pair, uint token0Amt) external view returns (uint token1Amt) {
        (uint reserve0, uint reserve1) = IPair(pair).getReserves();
        (uint64 _fee0, uint64 _fee1) = IPair(pair).getFeeRatio();
        return (token0Amt**2 * (MAX_FEE_RATIO - _fee0) / (MAX_FEE_RATIO - _fee1)).sqrt() * reserve1 / reserve0;
    }

}
