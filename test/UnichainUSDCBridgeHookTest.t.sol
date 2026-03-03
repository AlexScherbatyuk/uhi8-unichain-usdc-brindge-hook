// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {UnichainUSDCBridgeHook} from "../src/UnichainUSDCBridgeHook.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

contract UnichainUSDCBridgeHookTest is Test, Deployers {
    MockERC20 USDC;
    MockERC20 uUSDC; // our token to use in the ETH-TOKEN pool

    Currency usdcCurrency;
    Currency uusdcCurrency;

    UnichainUSDCBridgeHook hook;

    uint256 constant INITIAL_BALANCE = 101e6;

    function setUp() public {
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        // USDC
        USDC = new MockERC20("USDC", "USDC", 6);
        usdcCurrency = Currency.wrap(address(0));

        // uUSDC
        uUSDC = new MockERC20("Uniswao Virtual Tunnel", "uUSDC", 6);
        uusdcCurrency = Currency.wrap(address(0));

        // Mint tokens to the test contract
        uUSDC.mint(address(this), INITIAL_BALANCE); //type(uint128).max
        USDC.mint(address(this), INITIAL_BALANCE);

        // uUSDC.approve(address(poolManager), type(uint128).max);
        // USDC.approve(address(poolManager), type(uint128).max);

        // Deploy hook to an address that has the proper flags set
        //uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG);
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        deployCodeTo("UnichainUSDCBridgeHook.sol", abi.encode(manager, address(USDC)), address(flags));

        hook = UnichainUSDCBridgeHook(payable(address(flags)));

        uUSDC.approve(address(swapRouter), type(uint256).max);
        USDC.approve(address(swapRouter), type(uint256).max);

        //token.approve(address(modifyLiquidityRouter), type(uint256).max); // will be needed latter

        // Initialize a pool
        (key,) = initPool({
            _currency0: usdcCurrency,
            _currency1: uusdcCurrency,
            hooks: hook,
            fee: 0,
            tickSpacing: 60,
            sqrtPriceX96: SQRT_PRICE_1_1
        });

        // // Add liquidity to the pool, only for testing

        // USDC.approve(address(modifyLiquidityRouter), type(uint256).max); // will be needed latter
        // uUSDC.approve(address(modifyLiquidityRouter), type(uint256).max); // will be needed latter
        // // Add some liquidity to the pool
        // uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        // uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        // uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, 1e6);
        // uint256 tokenToAdd =
        //     LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceAtTickLower, SQRT_PRICE_1_1, liquidityDelta);

        // modifyLiquidityRouter.modifyLiquidity{value: 0}(
        //     key,
        //     ModifyLiquidityParams({
        //         tickLower: -60, tickUpper: 60, liquidityDelta: int256(uint256(liquidityDelta)), salt: bytes32(0)
        //     }),
        //     ZERO_BYTES
        // );
    }

    function testSwap() public {
        console.log("Before swap: USDC balance =", USDC.balanceOf(address(this)));
        console.log("Before swap: uUSDC balance =", uUSDC.balanceOf(address(this)));
        // Get the PoolId uint
        //uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        swapRouter.swap{value: 0}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -1e6, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        console.log("After swap: USDC balance =", USDC.balanceOf(address(this)));
        console.log("After swap: uUSDC balance =", uUSDC.balanceOf(address(this)));
    }
}
