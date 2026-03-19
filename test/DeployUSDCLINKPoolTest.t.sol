// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {USDCMock} from "./Mock/USDCMock.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployUSDCLINKPool} from "script/Deploy/DeployUSDCLINKPool.s.sol";
import {DeployUSDCLINKPoolHook} from "script/Deploy/DeployUSDCLINKPoolHook.s.sol";

contract DeployUSDCLINKPoolTest is Test, Deployers {
    USDCMock usdc;
    USDCMock link; // Using USDCMock for LINK (6 decimals for testing)

    HelperConfig helpConfig;
    HelperConfig.NetworkConfig config;

    DeployUSDCLINKPool deployer;
    IHooks hook;

    address _router;
    uint256 constant INITIAL_BALANCE = 1000e6; // 1000 USDC
    uint256 constant INITIAL_LINK_BALANCE = 1000e6; // 1000 LINK (6 decimals for testing)

    function setUp() public {
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();
        _router = makeAddr("router");

        DeployUSDCLINKPoolHook hookDeployer = new DeployUSDCLINKPoolHook();
        hook = IHooks(hookDeployer.deploy(address(manager)));

        // Create mock tokens
        usdc = new USDCMock("USDC", "USDC", 6);
        link = new USDCMock("LINK", "LINK", 6);

        // Mint tokens to the test contract
        usdc.mint(address(this), INITIAL_BALANCE);
        link.mint(address(this), INITIAL_LINK_BALANCE);

        // Approve tokens for swapRouter and modifyLiquidityRouter
        usdc.approve(address(swapRouter), type(uint256).max);
        link.approve(address(swapRouter), type(uint256).max);
        usdc.approve(address(modifyLiquidityRouter), type(uint256).max);
        link.approve(address(modifyLiquidityRouter), type(uint256).max);
    }

    /**
     * @dev Test pool deployment and initialization
     */
    function test_deployPool() public {
        // Deploy the pool using the deployer

        deployer = new DeployUSDCLINKPool();
        key = deployer.deploy(address(manager), address(hook));

        console.log("Pool deployed successfully");
        console.log("Currency0:", Currency.unwrap(key.currency0));
        console.log("Currency1:", Currency.unwrap(key.currency1));
        console.log("Fee:", key.fee);

        // Verify pool was initialized
        assertEq(key.fee, 3000);
        assertEq(key.tickSpacing, 60);
    }

    /**
     * @dev Test adding liquidity to the pool
     */
    function test_addLiquidity() public {
        _setupPool();

        uint256 initialUsdc = usdc.balanceOf(address(this));
        uint256 initialLink = link.balanceOf(address(this));

        console.log("Before adding liquidity:");
        console.log("USDC balance:", initialUsdc);
        console.log("LINK balance:", initialLink);

        // Calculate liquidity for token amounts
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, 100e6);

        // Add liquidity
        modifyLiquidityRouter.modifyLiquidity{value: 0}(
            key,
            ModifyLiquidityParams({
                tickLower: -60, tickUpper: 60, liquidityDelta: int256(uint256(liquidityDelta)), salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 finalUsdc = usdc.balanceOf(address(this));
        uint256 finalLink = link.balanceOf(address(this));

        console.log("After adding liquidity:");
        console.log("USDC balance:", finalUsdc);
        console.log("LINK balance:", finalLink);

        // Verify tokens were transferred
        assertLt(finalUsdc, initialUsdc, "USDC should decrease");
        assertLt(finalLink, initialLink, "LINK should decrease");
    }

    /**
     * @dev Test removing liquidity from the pool
     */
    function test_removeLiquidity() public {
        _setupPool();

        // First, add liquidity
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, 100e6);

        modifyLiquidityRouter.modifyLiquidity{value: 0}(
            key,
            ModifyLiquidityParams({
                tickLower: -60, tickUpper: 60, liquidityDelta: int256(uint256(liquidityDelta)), salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 afterAddUsdc = usdc.balanceOf(address(this));
        uint256 afterAddLink = link.balanceOf(address(this));

        console.log("After adding liquidity:");
        console.log("USDC balance:", afterAddUsdc);
        console.log("LINK balance:", afterAddLink);

        // Remove liquidity
        modifyLiquidityRouter.modifyLiquidity{value: 0}(
            key,
            ModifyLiquidityParams({
                tickLower: -60, tickUpper: 60, liquidityDelta: -int256(uint256(liquidityDelta)), salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        uint256 afterRemoveUsdc = usdc.balanceOf(address(this));
        uint256 afterRemoveLink = link.balanceOf(address(this));

        console.log("After removing liquidity:");
        console.log("USDC balance:", afterRemoveUsdc);
        console.log("LINK balance:", afterRemoveLink);

        // Verify tokens were returned (accounting for swap fees)
        assertGt(afterRemoveUsdc, afterAddUsdc, "USDC should increase after removal");
        assertGt(afterRemoveLink, afterAddLink, "LINK should increase after removal");
    }

    /**
     * @dev Test swapping USDC for LINK (zeroForOne = true)
     */
    function test_swapUSDCForLINK() public {
        _setupPoolWithLiquidity();

        uint256 beforeUsdc = usdc.balanceOf(address(this));
        uint256 beforeLink = link.balanceOf(address(this));

        console.log("Before swap:");
        console.log("USDC balance:", beforeUsdc);
        console.log("LINK balance:", beforeLink);

        // Swap 10 USDC for LINK
        int128 swapAmount = -int128(10e6); // negative = exact input
        bool zeroForOne = true;

        swapRouter.swap{value: 0}(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: swapAmount,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        uint256 afterUsdc = usdc.balanceOf(address(this));
        uint256 afterLink = link.balanceOf(address(this));

        console.log("After swap:");
        console.log("USDC balance:", afterUsdc);
        console.log("LINK balance:", afterLink);

        // Verify swap occurred
        assertEq(beforeUsdc - afterUsdc, 10e6, "USDC should decrease by 10");
        assertGt(afterLink, beforeLink, "LINK should increase");
    }

    /**
     * @dev Test swapping LINK for USDC (zeroForOne = false)
     */
    function test_swapLINKForUSDC() public {
        _setupPoolWithLiquidity();

        uint256 beforeUsdc = usdc.balanceOf(address(this));
        uint256 beforeLink = link.balanceOf(address(this));

        console.log("Before swap:");
        console.log("USDC balance:", beforeUsdc);
        console.log("LINK balance:", beforeLink);

        // Swap 10 LINK for USDC
        int128 swapAmount = -int128(10e6); // negative = exact input
        bool zeroForOne = false;

        swapRouter.swap{value: 0}(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: swapAmount,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        uint256 afterUsdc = usdc.balanceOf(address(this));
        uint256 afterLink = link.balanceOf(address(this));

        console.log("After swap:");
        console.log("USDC balance:", afterUsdc);
        console.log("LINK balance:", afterLink);

        // Verify swap occurred
        assertEq(beforeLink - afterLink, 10e6, "LINK should decrease by 10");
        assertGt(afterUsdc, beforeUsdc, "USDC should increase");
    }

    /**
     * @dev Test multiple swaps in sequence
     */
    function test_multipleSwaps() public {
        _setupPoolWithLiquidity();

        // Capture balances after liquidity is added but before swaps
        uint256 beforeFirstSwapUsdc = usdc.balanceOf(address(this));
        uint256 beforeFirstSwapLink = link.balanceOf(address(this));

        console.log("Starting multiple swaps test");
        console.log("Before swaps - USDC:", beforeFirstSwapUsdc);
        console.log("Before swaps - LINK:", beforeFirstSwapLink);

        // First swap: USDC -> LINK
        swapRouter.swap{value: 0}(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -int128(5e6), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        uint256 afterFirstSwapLink = link.balanceOf(address(this));
        uint256 afterFirstSwapUsdc = usdc.balanceOf(address(this));
        console.log("After first swap, LINK balance:", afterFirstSwapLink);
        console.log("After first swap, USDC balance:", afterFirstSwapUsdc);

        // Verify first swap increased LINK
        assertGt(afterFirstSwapLink, beforeFirstSwapLink, "LINK should increase after swapping USDC");

        // Second swap: LINK -> USDC
        swapRouter.swap{value: 0}(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -int128(2e6), sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        uint256 afterSecondSwapUsdc = usdc.balanceOf(address(this));
        uint256 afterSecondSwapLink = link.balanceOf(address(this));
        console.log("After second swap, USDC balance:", afterSecondSwapUsdc);
        console.log("After second swap, LINK balance:", afterSecondSwapLink);

        // Verify second swap increased USDC from the post-first-swap state
        assertGt(afterSecondSwapUsdc, afterFirstSwapUsdc, "USDC should increase after second swap");
        assertLt(afterSecondSwapLink, afterFirstSwapLink, "LINK should decrease after second swap");
    }

    // ============ Helper Functions ============

    /**
     * @dev Setup pool without initial liquidity
     */
    function _setupPool() internal {
        deployer = new DeployUSDCLINKPool();
        key = deployer.deploy(address(manager), address(hook));

        (Currency currency0, Currency currency1) = address(usdc) < address(link)
            ? (Currency.wrap(address(usdc)), Currency.wrap(address(link)))
            : (Currency.wrap(address(link)), Currency.wrap(address(usdc)));

        (key,) = initPool({
            _currency0: currency0,
            _currency1: currency1,
            hooks: hook,
            fee: 3000,
            tickSpacing: 60,
            sqrtPriceX96: SQRT_PRICE_1_1
        });
    }

    /**
     * @dev Setup pool with initial liquidity
     */
    function _setupPoolWithLiquidity() internal {
        _setupPool();

        // Add initial liquidity
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, 500e6);

        modifyLiquidityRouter.modifyLiquidity{value: 0}(
            key,
            ModifyLiquidityParams({
                tickLower: -60, tickUpper: 60, liquidityDelta: int256(uint256(liquidityDelta)), salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }
}
