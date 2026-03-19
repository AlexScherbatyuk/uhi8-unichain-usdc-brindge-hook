// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStaker} from "src/interfaces/IStaker.sol";

/**
 * @title USDCBridgeSender
 * @notice A contract for sending USDC tokens and arbitrary messages to receiver contracts on destination chains via Chainlink CCIP.
 */
contract USDCBridgeSender is Ownable2Step {
    using SafeERC20 for IERC20;

    enum Strategy {
        EOA,
        STAKER,
        CUSTOM
    }

    // Custom errors to provide more descriptive revert messages.
    error InvalidRouter(); // Used when the router address is 0
    error InvalidLinkToken(); // Used when the link token address is 0
    error InvalidUsdcToken(); // Used when the usdc token address is 0
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance to cover the fees.
    error InvalidDestinationChain(); // Used when the destination chain selector is 0.
    error InvalidReceiverAddress(); // Used when the receiver address is 0.
    error NoReceiverOnDestinationChain(uint64 destinationChainSelector); // Used when the receiver address is 0 for a
    // given destination chain.
    error AmountIsZero(); // Used if the amount to transfer is 0.
    error InvalidGasLimit(); // Used if the gas limit is 0.
    error NoGasLimitOnDestinationChain(uint64 destinationChainSelector); // Used when the gas limit is 0.

    event MessageSent( // The unique ID of the CCIP message.
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address indexed receiver,
        address target,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    IRouterClient internal immutable i_router;
    IERC20 internal immutable i_linkToken;
    IERC20 internal immutable i_usdcToken;

    // Mapping to keep track of the receiver contract per destination chain.
    mapping(uint64 => address) public s_receivers;
    // Mapping to store the gas limit per destination chain.
    mapping(uint64 => uint256) public s_gasLimits;

    modifier validateDestinationChain(uint64 _destinationChainSelector) {
        if (_destinationChainSelector == 0) revert InvalidDestinationChain();
        _;
    }

    /**
     * @notice Constructor initializes the contract with the router address.
     * @param _router The address of the router contract.
     * @param _link The address of the link contract.
     * @param _usdcToken The address of the usdc contract.
     */
    constructor(address _router, address _link, address _usdcToken, address _owner) Ownable(_owner) {
        if (_router == address(0)) revert InvalidRouter();
        if (_link == address(0)) revert InvalidLinkToken();
        if (_usdcToken == address(0)) revert InvalidUsdcToken();
        i_router = IRouterClient(_router);
        i_linkToken = IERC20(_link);
        i_usdcToken = IERC20(_usdcToken);
    }

    /**
     * @notice Set the receiver contract for a given destination chain.
     * @dev This function can only be called by the owner.
     * @param _destinationChainSelector The selector of the destination chain.
     * @param _receiver The receiver contract on the destination chain.
     */
    function setReceiverForDestinationChain(uint64 _destinationChainSelector, address _receiver)
        external
        onlyOwner
        validateDestinationChain(_destinationChainSelector)
    {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        s_receivers[_destinationChainSelector] = _receiver;
    }

    /**
     * @notice Set the gas limit for a given destination chain.
     * @dev This function can only be called by the owner.
     * @param _destinationChainSelector The selector of the destination chain.
     * @param _gasLimit The gas limit on the destination chain.
     */
    function setGasLimitForDestinationChain(uint64 _destinationChainSelector, uint256 _gasLimit)
        external
        onlyOwner
        validateDestinationChain(_destinationChainSelector)
    {
        if (_gasLimit == 0) revert InvalidGasLimit();
        s_gasLimits[_destinationChainSelector] = _gasLimit;
    }

    /**
     * @notice Delete the receiver contract for a given destination chain.
     * @dev This function can only be called by the owner.
     * @param _destinationChainSelector The selector of the destination chain.
     */
    function deleteReceiverForDestinationChain(uint64 _destinationChainSelector)
        external
        onlyOwner
        validateDestinationChain(_destinationChainSelector)
    {
        if (s_receivers[_destinationChainSelector] == address(0)) {
            revert NoReceiverOnDestinationChain(_destinationChainSelector);
        }
        delete s_receivers[_destinationChainSelector];
    }

    /**
     * @notice Sends USDC tokens and message data to the receiver on the destination chain, paying fees in LINK.
     * @dev Assumes contract has sufficient LINK to pay for CCIP fees. Only callable by owner.
     * @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
     * @param _beneficiary The beneficiary address for the stake/transfer on the destination chain.
     * @param _amount The amount of USDC tokens to transfer.
     * @param _strategy The strategy for handling the transfer (EOA, STAKER, or AAVE).
     * @return messageId The ID of the CCIP message that was sent.
     */
    function sendMessagePayLINK(
        uint64 _destinationChainSelector,
        address _beneficiary,
        uint256 _amount,
        uint256 _strategy,
        bytes memory _data
    ) public onlyOwner validateDestinationChain(_destinationChainSelector) returns (bytes32 messageId) {
        address receiver = s_receivers[_destinationChainSelector];
        if (receiver == address(0)) {
            revert NoReceiverOnDestinationChain(_destinationChainSelector);
        }
        if (_amount == 0) revert AmountIsZero();
        uint256 gasLimit = s_gasLimits[_destinationChainSelector];
        if (gasLimit == 0) {
            revert NoGasLimitOnDestinationChain(_destinationChainSelector);
        }
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        // address(linkToken) means fees are paid in LINK
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(i_usdcToken), amount: _amount});
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // ABI-encoded receiver address
            data: abi.encode(_beneficiary, _strategy, _amount, _data), // Packed encoding to reduce data size for CCIP limits
            // data: _strategy == 0
            //     ? abi.encodeWithSelector(IERC20.transfer.selector, _beneficiary, _amount)
            //     : abi.encodeWithSelector(IStaker.stake.selector, _beneficiary, _amount),
            tokenAmounts: tokenAmounts, // The amount and type of token being transferred
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: gasLimit, // Gas limit for the callback on the destination chain
                    allowOutOfOrderExecution: true // Allows the message to be executed out of order relative to other messages
                })
            ),
            // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
            feeToken: address(i_linkToken)
        });

        // Get the fee required to send the CCIP message
        uint256 fees = i_router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > i_linkToken.balanceOf(address(this))) {
            revert NotEnoughBalance(i_linkToken.balanceOf(address(this)), fees);
        }

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        i_linkToken.approve(address(i_router), fees);

        // approve the Router to spend usdc tokens on contract's behalf. It will spend the amount of the given token
        i_usdcToken.approve(address(i_router), _amount);

        // Send the message through the router and store the returned message ID
        messageId = i_router.ccipSend(_destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(
            messageId,
            _destinationChainSelector,
            receiver,
            _beneficiary,
            address(i_usdcToken),
            _amount,
            address(i_linkToken),
            fees
        );

        // Return the message ID
        return messageId;
    }
}
