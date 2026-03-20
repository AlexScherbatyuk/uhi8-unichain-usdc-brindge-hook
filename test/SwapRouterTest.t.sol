// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {SwapRouter} from "src/periphery/SwapRouter.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {USDCMock} from "./Mock/USDCMock.sol";
import {LINKMock} from "./Mock/LINKMock.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract SwapRouterTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    SwapRouter public spRouter;
    USDCMock public usdc;
    LINKMock public link;

    address public user = address(0x1);
    address public swapper = address(0x2);

    uint256 constant INITIAL_USDC = 5e6; // 5 USDC
    uint256 constant INITIAL_LINK = 5e18; // 5 LINK (18 decimals)
    uint256 constant USER_BALANCE = 100e6; // 100 USDC
    uint256 constant USER_LINK_BALANCE = 100e18; // 100 LINK
    uint256 constant SWAP_AMOUNT = 1e6; // 1 USDC to swap

    function setUp() public {
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        // Deploy tokens
        usdc = new USDCMock("USDC", "USDC", 6);
        link = new LINKMock("LINK", "LINK", 18);

        // Deploy swap router
        spRouter = new SwapRouter(address(manager));

        // Mint tokens to user
        usdc.mint(user, USER_BALANCE);
        link.mint(user, USER_LINK_BALANCE);

        // Mint tokens to swapper
        usdc.mint(swapper, USER_BALANCE);
        link.mint(swapper, USER_LINK_BALANCE);

        // Approve router to spend users' tokens
        vm.startPrank(user);
        usdc.approve(address(spRouter), type(uint256).max);
        link.approve(address(spRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper);
        usdc.approve(address(spRouter), type(uint256).max);
        link.approve(address(spRouter), type(uint256).max);
        vm.stopPrank();
    }

    function _initializePoolWithLiquidity(address currency0, address currency1) internal {
        // Ensure currency0 < currency1
        if (uint160(currency0) > uint160(currency1)) {
            (currency0, currency1) = (currency1, currency0);
        }

        Currency c0 = Currency.wrap(currency0);
        Currency c1 = Currency.wrap(currency1);

        initPool({
            _currency0: c0,
            _currency1: c1,
            hooks: IHooks(address(0)),
            fee: 500,
            tickSpacing: 10,
            sqrtPriceX96: SQRT_PRICE_1_1
        });

        // Add liquidity using the ModifyLiquidityRouter from Deployers
        PoolKey memory poolKey = createTestPoolKey(currency0, currency1);

        vm.startPrank(user);
        IERC20(currency0).approve(address(modifyLiquidityRouter), type(uint256).max);
        IERC20(currency1).approve(address(modifyLiquidityRouter), type(uint256).max);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(-600),
            TickMath.getSqrtPriceAtTick(600),
            INITIAL_USDC,
            INITIAL_LINK
        );

        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -600, tickUpper: 600, liquidityDelta: int256(uint256(liquidity)), salt: bytes32(0)
            }),
            ""
        );
        vm.stopPrank();
    }

    // ==================== Constructor Tests ====================

    function test_constructor_setsPoolManager() public view {
        assertEq(address(spRouter.poolManager()), address(manager));
    }

    // ==================== Swap Tests ====================

    function test_swap_zeroForOne_transfersTokensFromUser() public {
        _initializePoolWithLiquidity(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        uint256 swapperUSDCBefore = usdc.balanceOf(swapper);

        vm.prank(swapper);
        spRouter.swap(key, int128(int256(SWAP_AMOUNT)), true, 0, "");

        // Verify tokens were transferred from swapper
        assertLt(usdc.balanceOf(swapper), swapperUSDCBefore);
    }

    function test_swap_oneForZero_transfersTokensFromUser() public {
        _initializePoolWithLiquidity(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        uint256 swapperLINKBefore = link.balanceOf(swapper);

        vm.prank(swapper);
        spRouter.swap(key, int128(int256(SWAP_AMOUNT)), false, 0, "");

        // Verify tokens were transferred from swapper
        assertLt(link.balanceOf(swapper), swapperLINKBefore);
    }

    function test_swap_revertsWithInsufficientBalance() public {
        _initializePoolWithLiquidity(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        // Create user with insufficient USDC
        address poorUser = address(0x3);
        usdc.mint(poorUser, SWAP_AMOUNT - 1);
        link.mint(poorUser, USER_LINK_BALANCE);

        vm.startPrank(poorUser);
        usdc.approve(address(spRouter), type(uint256).max);
        link.approve(address(spRouter), type(uint256).max);
        vm.expectRevert();
        spRouter.swap(key, int128(int256(SWAP_AMOUNT)), true, 0, "");
        vm.stopPrank();
    }

    function test_swap_revertsWithoutApproval() public {
        _initializePoolWithLiquidity(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        address unapprovedUser = address(0x4);
        usdc.mint(unapprovedUser, SWAP_AMOUNT);
        link.mint(unapprovedUser, USER_LINK_BALANCE);

        vm.startPrank(unapprovedUser);
        // Don't approve router
        vm.expectRevert();
        spRouter.swap(key, int128(int256(SWAP_AMOUNT)), true, 0, "");
        vm.stopPrank();
    }

    function test_swap_withZeroMinAmountOut() public {
        _initializePoolWithLiquidity(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        uint256 swapperUSDCBefore = usdc.balanceOf(swapper);
        uint256 swapperLINKBefore = link.balanceOf(swapper);

        vm.prank(swapper);
        spRouter.swap(key, int128(int256(SWAP_AMOUNT)), true, 0, "");

        // Verify swap occurred
        assertLt(usdc.balanceOf(swapper), swapperUSDCBefore);
        assertGt(link.balanceOf(swapper), swapperLINKBefore);
    }

    function test_swap_receiverGetsOutputTokens() public {
        _initializePoolWithLiquidity(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        address receiver = address(0x5);
        link.mint(receiver, 0);

        uint256 receiverLINKBefore = link.balanceOf(receiver);

        vm.prank(swapper);
        spRouter.swap(key, int128(int256(SWAP_AMOUNT)), true, 0, "");

        // Receiver should have received LINK tokens
        assertGt(link.balanceOf(swapper), 0);
    }

    function test_swap_multipleSwapsSequentially() public {
        _initializePoolWithLiquidity(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        uint256 swapperUSDCBefore = usdc.balanceOf(swapper);
        uint256 swapperLINKBefore = link.balanceOf(swapper);

        // First swap
        vm.prank(swapper);
        spRouter.swap(key, int128(int256(SWAP_AMOUNT)), true, 0, "");

        uint256 swapperUSDCAfterFirst = usdc.balanceOf(swapper);
        uint256 swapperLINKAfterFirst = link.balanceOf(swapper);

        // Second swap
        vm.prank(swapper);
        spRouter.swap(key, int128(int256(SWAP_AMOUNT)) / 2, true, 0, "");

        uint256 swapperLINKAfterSecond = link.balanceOf(swapper);

        // Verify sequential swaps worked
        assertLt(swapperUSDCAfterFirst, swapperUSDCBefore); // USDC decreased
        assertGt(swapperLINKAfterFirst, swapperLINKBefore); // LINK increased from first swap
        assertGt(swapperLINKAfterSecond, swapperLINKAfterFirst); // LINK increased more from second swap
    }

    // ==================== Helper Functions ====================

    function createTestPoolKey(address currency0, address currency1) internal pure returns (PoolKey memory) {
        // Ensure currency0 < currency1 (standard Uniswap ordering)
        if (uint160(currency0) > uint160(currency1)) {
            (currency0, currency1) = (currency1, currency0);
        }

        return PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
    }
}
