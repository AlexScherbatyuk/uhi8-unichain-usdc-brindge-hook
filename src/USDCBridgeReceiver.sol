// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {IStaker} from "src/interfaces/IStaker.sol";

/**
 * @title USDCBridgeReceiver
 * @author Alexander Scherbatyuk (http://x.com/AlexScherbatyuk)
 * @notice Receiver endpoint for the Unichain USDC Bridge that receives cross-chain USDC tokens via Chainlink CCIP and delegates stake calls.
 * @dev Processes cross-chain messages, manages failed message recovery, and handles token transfers to staking contracts.
 */
contract USDCBridgeReceiver is CCIPReceiver, Ownable2Step {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    /// @notice Thrown when the USDC token address is zero.
    error InvalidUsdcToken();

    /// @notice Thrown when the staker contract address is zero.
    error InvalidStaker();

    /// @notice Thrown when the source chain selector is zero.
    error InvalidSourceChain();

    /// @notice Thrown when a sender address is zero.
    error InvalidSenderAddress();

    /// @notice Thrown when no sender is configured for the given source chain.
    error NoSenderOnSourceChain(uint64 sourceChainSelector);

    /// @notice Thrown when the message sender is not the configured sender for the source chain.
    error WrongSenderForSourceChain(uint64 sourceChainSelector);

    /// @notice Thrown when a function is called from outside the contract itself.
    error OnlySelf();

    /// @notice Thrown when the received token differs from the expected USDC token.
    error WrongReceivedToken(address usdcToken, address receivedToken);

    /// @notice Thrown when the call to the staker contract fails.
    error CallToStakerFailed();

    /// @notice Thrown when the staker contract call returns data (none is expected).
    error NoReturnDataExpected();

    /// @notice Thrown when attempting to retry a message that has not failed.
    error MessageNotFailed(bytes32 messageId);

    /**
     * @notice Emitted when a message is successfully received and processed from another chain.
     * @param messageId The unique ID of the CCIP message.
     * @param sourceChainSelector The chain selector of the source chain.
     * @param sender The address of the sender from the source chain.
     * @param data The call data that was received.
     * @param token The token address that was transferred.
     * @param tokenAmount The token amount that was transferred.
     */
    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address indexed sender,
        bytes data,
        address token,
        uint256 tokenAmount
    );

    /**
     * @notice Emitted when a message fails to process.
     * @param messageId The unique ID of the CCIP message that failed.
     * @param reason The reason for the failure.
     */
    event MessageFailed(bytes32 indexed messageId, bytes reason);

    /**
     * @notice Emitted when a failed message is recovered by transferring tokens to a beneficiary.
     * @param messageId The unique ID of the recovered CCIP message.
     */
    event MessageRecovered(bytes32 indexed messageId);

    /**
     * @notice Error codes for tracking the status of messages.
     * @dev RESOLVED is first to ensure the default value (0) represents a resolved state.
     */
    enum ErrorCode {
        RESOLVED,
        FAILED
    }

    /**
     * @notice Struct to store information about a failed message.
     * @param messageId The unique ID of the failed CCIP message.
     * @param errorCode The error code indicating the message status (RESOLVED or FAILED).
     */
    struct FailedMessage {
        bytes32 messageId;
        ErrorCode errorCode;
    }

    /// @notice The USDC token contract.
    IERC20 private immutable i_usdcToken;

    /// @notice The staker contract address where tokens are delegated.
    address private immutable i_staker;

    /// @notice Mapping of source chain selectors to authorized sender addresses on those chains.
    mapping(uint64 => address) public s_senders;

    /// @notice Stores the message contents of failed CCIP messages for recovery purposes.
    mapping(bytes32 => Client.Any2EVMMessage) public s_messageContents;

    /// @notice EnumerableMap tracking failed messages and their status (FAILED or RESOLVED).
    EnumerableMap.Bytes32ToUintMap internal s_failedMessages;

    modifier validateSourceChain(uint64 _sourceChainSelector) {
        if (_sourceChainSelector == 0) revert InvalidSourceChain();
        _;
    }

    /**
     * @dev Modifier to allow only the contract itself to execute a function.
     * Throws an exception if called by any account other than the contract itself.
     */
    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    /**
     * @notice Constructor initializes the contract with the router address.
     * @param _router The address of the router contract.
     * @param _usdcToken The address of the usdc contract.
     * @param _staker The address of the staker contract.
     */
    constructor(address _router, address _usdcToken, address _staker) CCIPReceiver(_router) Ownable(msg.sender) {
        if (_usdcToken == address(0)) revert InvalidUsdcToken();
        if (_staker == address(0)) revert InvalidStaker();
        i_usdcToken = IERC20(_usdcToken);
        i_staker = _staker;
        i_usdcToken.approve(_staker, type(uint256).max);
    }

    /**
     * @notice Set the sender contract for a given source chain.
     * @dev This function can only be called by the owner.
     * @param _sourceChainSelector The selector of the source chain.
     * @param _sender The sender contract on the source chain.
     */
    function setSenderForSourceChain(uint64 _sourceChainSelector, address _sender)
        external
        onlyOwner
        validateSourceChain(_sourceChainSelector)
    {
        if (_sender == address(0)) revert InvalidSenderAddress();
        s_senders[_sourceChainSelector] = _sender;
    }

    /**
     * @notice Delete the sender contract for a given source chain.
     * @dev This function can only be called by the owner.
     * @param _sourceChainSelector The selector of the source chain.
     */
    function deleteSenderForSourceChain(uint64 _sourceChainSelector)
        external
        onlyOwner
        validateSourceChain(_sourceChainSelector)
    {
        if (s_senders[_sourceChainSelector] == address(0)) {
            revert NoSenderOnSourceChain(_sourceChainSelector);
        }
        delete s_senders[_sourceChainSelector];
    }

    /**
     * @notice The entrypoint for the CCIP router to call. This function should
     * never revert, all errors should be handled internally in this contract.
     * @dev Extremely important to ensure only router calls this.
     * @param any2EvmMessage The message to process.
     */
    function ccipReceive(Client.Any2EVMMessage calldata any2EvmMessage) external override onlyRouter {
        // Validate that the message sender matches the configured sender for this source chain
        if (abi.decode(any2EvmMessage.sender, (address)) != s_senders[any2EvmMessage.sourceChainSelector]) {
            revert WrongSenderForSourceChain(any2EvmMessage.sourceChainSelector);
        }

        // Process the message with error handling to prevent CCIP from reverting
        /* solhint-disable no-empty-blocks */
        try this.processMessage(any2EvmMessage) {
        // Message processed successfully; no further action needed
        }

            /* solhint-enable no-empty-blocks */
            catch (bytes memory err) {
            // Store the failed message for later recovery
            s_failedMessages.set(any2EvmMessage.messageId, uint256(ErrorCode.FAILED));
            s_messageContents[any2EvmMessage.messageId] = any2EvmMessage;
            // Emit event instead of reverting to allow manual recovery via retryFailedMessage
            emit MessageFailed(any2EvmMessage.messageId, err);
            return;
        }
    }

    /**
     * @notice Serves as the entry point for this contract to process incoming messages.
     * @dev Transfers specified token amounts to the owner of this contract. This function
     * must be external because of the try/catch for error handling.
     * It uses the `onlySelf`: can only be called from the contract.
     * @param any2EvmMessage Received CCIP message.
     */
    function processMessage(Client.Any2EVMMessage calldata any2EvmMessage) external onlySelf {
        _ccipReceive(any2EvmMessage); // process the message - may revert
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        // Verify the received token is the expected USDC token
        if (any2EvmMessage.destTokenAmounts[0].token != address(i_usdcToken)) {
            revert WrongReceivedToken(address(i_usdcToken), any2EvmMessage.destTokenAmounts[0].token);
        }

        // Decode the call data: target address, original message sender, and function call data
        // (address _beneficiary, uint256 _strategy, uint256 _amount) =
        //     abi.decode(any2EvmMessage.data, (address, uint256, uint256));

        // Execute the low-level call to the staker contract with the encoded function selector and arguments
        bool success;
        bytes memory returnData;

        (address _beneficiary, uint256 _strategy, uint256 _amount, bytes memory _data) =
            abi.decode(any2EvmMessage.data, (address, uint256, uint256, bytes));

        if (_strategy == 0) {
            IERC20(i_usdcToken).safeTransfer(_beneficiary, _amount);
        }
        if (_strategy == 1) {
            IStaker(i_staker).stake(_beneficiary, _amount);
        }

        if (_strategy >= 2) {
            if (any2EvmMessage.data.length > 0) {
                (success, returnData) = _beneficiary.call(_data);
            } else {
                revert CallToStakerFailed();
            }
        }
        if (!success) revert CallToStakerFailed();
        if (returnData.length > 0) revert NoReturnDataExpected();

        // Emit success event with message details
        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address)),
            any2EvmMessage.data,
            any2EvmMessage.destTokenAmounts[0].token,
            any2EvmMessage.destTokenAmounts[0].amount
        );
    }

    /**
     * @notice Allows the owner to retry a failed message in order to unblock the associated tokens.
     * @dev This function is only callable by the contract owner. It changes the status of the message
     * from 'failed' to 'resolved' to prevent reentry and multiple retries of the same message.
     * @param messageId The unique identifier of the failed message.
     * @param beneficiary The address to which the tokens will be sent.
     */
    function retryFailedMessage(bytes32 messageId, address beneficiary) external onlyOwner {
        // Check if the message has failed; if not, revert the transaction.
        if (s_failedMessages.get(messageId) != uint256(ErrorCode.FAILED)) {
            revert MessageNotFailed(messageId);
        }

        // Set the error code to RESOLVED to disallow reentry and multiple retries of the same failed message.
        s_failedMessages.set(messageId, uint256(ErrorCode.RESOLVED));

        // Retrieve the content of the failed message.
        Client.Any2EVMMessage memory message = s_messageContents[messageId];

        // This example expects one token to have been sent.
        // Transfer the associated tokens to the specified receiver as an escape hatch.
        IERC20(message.destTokenAmounts[0].token).safeTransfer(beneficiary, message.destTokenAmounts[0].amount);

        // Emit an event indicating that the message has been recovered.
        emit MessageRecovered(messageId);
    }

    /**
     * @notice Retrieves a paginated list of failed messages.
     * @dev This function returns a subset of failed messages defined by `offset` and `limit` parameters. It ensures that
     * the pagination parameters are within the bounds of the available data set.
     * @param offset The index of the first failed message to return, enabling pagination by skipping a specified number
     * of messages from the start of the dataset.
     * @param limit The maximum number of failed messages to return, restricting the size of the returned array.
     * @return failedMessages An array of `FailedMessage` struct, each containing a `messageId` and an `errorCode`
     * (RESOLVED or FAILED), representing the requested subset of failed messages. The length of the returned array is
     * determined by the `limit` and the total number of failed messages.
     */
    function getFailedMessages(uint256 offset, uint256 limit) external view returns (FailedMessage[] memory) {
        uint256 length = s_failedMessages.length();

        // Calculate the actual number of items to return (can't exceed total length or requested limit)
        uint256 returnLength = (offset + limit > length) ? length - offset : limit;
        FailedMessage[] memory failedMessages = new FailedMessage[](returnLength);

        // Adjust loop to respect pagination (start at offset, end at offset + limit or total length)
        for (uint256 i = 0; i < returnLength; i++) {
            (bytes32 messageId, uint256 errorCode) = s_failedMessages.at(offset + i);
            failedMessages[i] = FailedMessage(messageId, ErrorCode(errorCode));
        }
        return failedMessages;
    }
}
