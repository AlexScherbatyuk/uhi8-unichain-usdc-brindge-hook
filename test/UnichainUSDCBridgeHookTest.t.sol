// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
// import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {UnichainUSDCBridgeHook} from "../src/UnichainUSDCBridgeHook.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {USDTMock} from "./Mock/USDTMock.sol";
import {USDCMock} from "./Mock/USDCMock.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract UnichainUSDCBridgeHookTest is Test, Deployers {
    USDCMock USDC;
    USDTMock USDT; // our token to use in the ETH-TOKEN pool

    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    UnichainUSDCBridgeHook hook;

    address _router;
    uint64 _destinationChainSelector;

    uint256 constant INITIAL_BALANCE = 101e6;

    uint160 flags = uint160(
        Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
            | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
            | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG
    );

    function setUp() public {
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();
        _router = makeAddr("router");
        _destinationChainSelector = 1;

        helpConfig = new HelperConfig();
        config = helpConfig.getConfig();
    }

    modifier initializeZeroOnePool() {
        USDC = new USDCMock("USDC", "USDC", 6);
        USDT = new USDTMock("USDT", "USDT", 6);
        _deploy();
        _;
    }

    modifier initializeOneZeroPool() {
        USDT = new USDTMock("USDT", "USDT", 6);
        USDC = new USDCMock("USDC", "USDC", 6);
        _deploy();
        _;
    }

    function _deploy() public {
        (currency0, currency1) = address(USDC) < address(USDT)
            ? (Currency.wrap(address(USDC)), Currency.wrap(address(USDT)))
            : (Currency.wrap(address(USDT)), Currency.wrap(address(USDC)));

        // Mint tokens to the test contract
        USDT.mint(address(this), INITIAL_BALANCE); //type(uint128).max
        USDC.mint(address(this), INITIAL_BALANCE);

        deployCodeTo(
            "UnichainUSDCBridgeHook.sol",
            abi.encode(
                manager,
                address(USDC),
                address(config.linkTokens[0]),
                address(config.ccipRouters[0]),
                config.usdcLinkPoolHook,
                config.destinationChainSelectors[0]
            ),
            address(flags)
        );

        hook = UnichainUSDCBridgeHook(payable(address(flags)));

        USDT.approve(address(swapRouter), type(uint256).max);
        USDT.approve(address(hook), type(uint256).max);

        USDC.approve(address(swapRouter), type(uint256).max);
        USDC.approve(address(hook), type(uint256).max);

        (key,) = initPool({
            _currency0: currency0,
            _currency1: currency1,
            hooks: hook,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            sqrtPriceX96: SQRT_PRICE_1_1
        });

        // Add liquidity to the pool, only for testing

        USDC.approve(address(modifyLiquidityRouter), type(uint256).max); // will be needed latter
        USDT.approve(address(modifyLiquidityRouter), type(uint256).max); // will be needed latter
        // Add some liquidity to the pool
        // uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, 10e6);
        // uint256 tokenToAdd =
        //     LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceAtTickLower, SQRT_PRICE_1_1, liquidityDelta);

        modifyLiquidityRouter.modifyLiquidity{value: 0}(
            key,
            ModifyLiquidityParams({
                tickLower: -60, tickUpper: 60, liquidityDelta: int256(uint256(liquidityDelta)), salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_zeroOneBeforeSwapBridge() public initializeZeroOnePool {
        console.log("Before swap: USDC balance  =", USDC.balanceOf(address(this)));
        console.log("Before swap: USDT balance  =", USDT.balanceOf(address(this)));

        // Set user address in hook data
        bytes memory hookData = abi.encode(
            address(this), UnichainUSDCBridgeHook.MessageData({target: address(0), callData: "", minAmountOut: 0}), true
        );
        //int128 swapAmount = exactInput ? -int128(1e6) : int128(1e6);
        int128 swapAmount = -int128(1e6);
        bool zeroForOne = true;

        swapRouter.swap{value: 0}(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: swapAmount,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        console.log("After swap: USDC balance   =", USDC.balanceOf(address(this)));
        console.log("After swap: USDT balance   =", USDT.balanceOf(address(this)));
        console.log("Hook usdc balance:         =", USDC.balanceOf(address(hook)));
        console.log("Hook USDT balance:         =", USDT.balanceOf(address(hook)));
        console.log("manager usdc balance:      =", USDC.balanceOf(address(manager)));
        console.log("manager USDT balance:      =", USDT.balanceOf(address(manager)));

        assertGe(
            USDC.balanceOf(address(hook)),
            swapAmount > 0 ? uint256(int256(swapAmount)) : uint256(-int256(swapAmount)),
            "Hook holds USDC"
        );
    }

    function test_oneZeroBeforeSwapBridge() public initializeOneZeroPool {
        console.log("Before swap: USDC balance  =", USDC.balanceOf(address(this)));
        console.log("Before swap: USDT balance  =", USDT.balanceOf(address(this)));

        // Set user address in hook data
        bytes memory hookData = abi.encode(
            address(this), UnichainUSDCBridgeHook.MessageData({target: address(0), callData: "", minAmountOut: 0}), true
        );
        int128 swapAmount = -int128(1e6);
        bool zeroForOne = false;

        swapRouter.swap{value: 0}(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: swapAmount,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        console.log("After swap: USDC balance   =", USDC.balanceOf(address(this)));
        console.log("After swap: USDT balance   =", USDT.balanceOf(address(this)));
        console.log("Hook usdc balance:         =", USDC.balanceOf(address(hook)));
        console.log("Hook USDT balance:         =", USDT.balanceOf(address(hook)));
        console.log("manager usdc balance:      =", USDC.balanceOf(address(manager)));
        console.log("manager USDT balance:      =", USDT.balanceOf(address(manager)));

        assertGe(
            USDC.balanceOf(address(hook)),
            swapAmount > 0 ? uint256(int256(swapAmount)) : uint256(-int256(swapAmount)),
            "Hook holds USDC"
        );
    }

    function test_zeroOneAfterSwapBrigde() public initializeOneZeroPool {
        // USDT/USDC pool
        uint256 usdcBalance = USDC.balanceOf(address(this));
        uint256 usdtBalance = USDT.balanceOf(address(this));
        console.log("Before swap: USDC balance  =", usdcBalance);
        console.log("Before swap: USDT balance  =", usdtBalance);

        // Set user address in hook data

        bytes memory hookData = abi.encode(
            address(this), UnichainUSDCBridgeHook.MessageData({target: address(0), callData: "", minAmountOut: 0}), true
        );
        int128 swapAmount = -int128(1e6);
        bool zeroForOne = false;

        swapRouter.swap{value: 0}(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: swapAmount,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
        uint256 usdcBalanceAfter = USDC.balanceOf(address(this));
        uint256 usdtBalanceAfter = USDT.balanceOf(address(this));
        console.log("After swap: USDC balance   =", usdcBalanceAfter);
        console.log("After swap: USDT balance   =", usdtBalanceAfter);
        console.log("Hook usdc balance:         =", USDC.balanceOf(address(hook)));
        console.log("Hook USDT balance:         =", USDT.balanceOf(address(hook)));
        console.log("manager usdc balance:      =", USDC.balanceOf(address(manager)));
        console.log("manager USDT balance:      =", USDT.balanceOf(address(manager)));

        // assertGt(usdcBalanceAfter, usdcBalance, "USDC amount has increased");
        // assertGt(usdtBalance, usdtBalanceAfter, "USDT amount has decreased");
    }

    function test_oneZeroAfterSwapBrigde() public initializeZeroOnePool {
        // USDC/USDT pool
        uint256 usdcBalance = USDC.balanceOf(address(this));
        uint256 usdtBalance = USDT.balanceOf(address(this));
        console.log("Before swap: USDC balance  =", usdcBalance);
        console.log("Before swap: USDT balance  =", usdtBalance);

        // Set user address in hook data
        bytes memory hookData = abi.encode(
            address(this), UnichainUSDCBridgeHook.MessageData({target: address(0), callData: "", minAmountOut: 0}), true
        );
        int128 swapAmount = -int128(1e6);
        bool zeroForOne = true;

        swapRouter.swap{value: 0}(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: swapAmount,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
        uint256 usdcBalanceAfter = USDC.balanceOf(address(this));
        uint256 usdtBalanceAfter = USDT.balanceOf(address(this));
        console.log("After swap: USDC balance   =", usdcBalanceAfter);
        console.log("After swap: USDT balance   =", usdtBalanceAfter);
        console.log("Hook usdc balance:         =", USDC.balanceOf(address(hook)));
        console.log("Hook USDT balance:         =", USDT.balanceOf(address(hook)));
        console.log("manager usdc balance:      =", USDC.balanceOf(address(manager)));
        console.log("manager USDT balance:      =", USDT.balanceOf(address(manager)));

        // assertGt(usdcBalanceAfter, usdcBalance, "USDC amount has increased");
        // assertGt(usdtBalance, usdtBalanceAfter, "USDT amount has decreased");
    }

    function test_afterAddLiquidityBridgeSkip() public initializeZeroOnePool {
        uint256 liqudityAmountToAdd = 10e6;
        // uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint128 liquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, liqudityAmountToAdd);
        // uint256 tokenToAdd =
        //     LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceAtTickLower, SQRT_PRICE_1_1, liquidityDelta);

        modifyLiquidityRouter.modifyLiquidity{value: 0}(
            key,
            ModifyLiquidityParams({
                tickLower: -60, tickUpper: 60, liquidityDelta: int256(uint256(liquidityDelta)), salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        console.log("PoolManage USDC reserves:  ", USDC.balanceOf(address(manager)));
        console.log("PoolManage USDT reserves:  ", USDT.balanceOf(address(manager)));
    }

    function test_afterAddLiquidityBridge() public initializeZeroOnePool {
        bytes memory hookData = abi.encode(
            address(this), UnichainUSDCBridgeHook.MessageData({target: address(0), callData: "", minAmountOut: 0}), true
        );
        uint256 liqudityAmountToAdd = 10e6;
        // uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint128 liquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, liqudityAmountToAdd);
        // uint256 tokenToAdd =
        //     LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceAtTickLower, SQRT_PRICE_1_1, liquidityDelta);

        modifyLiquidityRouter.modifyLiquidity{value: 0}(
            key,
            ModifyLiquidityParams({
                tickLower: -60, tickUpper: 60, liquidityDelta: int256(uint256(liquidityDelta)), salt: bytes32(0)
            }),
            hookData
        );

        console.log("PoolManage USDC reserves:  ", USDC.balanceOf(address(manager)));
        console.log("PoolManage USDT reserves:  ", USDT.balanceOf(address(manager)));
        console.log("hook USDC reserves:        ", USDC.balanceOf(address(hook)));
        console.log("hook USDT reserves:        ", USDT.balanceOf(address(hook)));
    }

    function test_afterAddLiquidityBridgeReversToken() public initializeOneZeroPool {
        bytes memory hookData = abi.encode(
            address(this), UnichainUSDCBridgeHook.MessageData({target: address(0), callData: "", minAmountOut: 0}), true
        );
        uint256 liqudityAmountToAdd = 10e6;
        // uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint128 liquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, liqudityAmountToAdd);
        // uint256 tokenToAdd =
        //     LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceAtTickLower, SQRT_PRICE_1_1, liquidityDelta);

        modifyLiquidityRouter.modifyLiquidity{value: 0}(
            key,
            ModifyLiquidityParams({
                tickLower: -60, tickUpper: 60, liquidityDelta: int256(uint256(liquidityDelta)), salt: bytes32(0)
            }),
            hookData
        );

        console.log("PoolManage USDC reserves:  ", USDC.balanceOf(address(manager)));
        console.log("PoolManage USDT reserves:  ", USDT.balanceOf(address(manager)));
        console.log("hook USDC reserves:        ", USDC.balanceOf(address(hook)));
        console.log("hook USDT reserves:        ", USDT.balanceOf(address(hook)));
    }
}
