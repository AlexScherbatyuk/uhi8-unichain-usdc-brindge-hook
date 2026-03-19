// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {LiquidityRouter} from "src/Periphery/LiquidityRouter.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {USDCMock} from "./Mock/USDCMock.sol";
import {USDTMock} from "./Mock/USDTMock.sol";
import {LINKMock} from "./Mock/LINKMock.sol";

contract LiquidityRouterTest is Test, Deployers {
    using CurrencyLibrary for Currency;

    LiquidityRouter public router;
    USDCMock public usdc;
    LINKMock public link;
    USDTMock public usdt;

    address public user = address(0x1);
    uint256 constant INITIAL_USDC = 5e6; // 5 USDC
    uint256 constant INITIAL_LINK = 5e18; // 5 LINK (18 decimals)
    uint256 constant USER_BALANCE = 100e6; // 100 USDC / USDT
    uint256 constant USER_LINK_BALANCE = 100e18; // 100 LINK

    function setUp() public {
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        // Deploy tokens
        usdc = new USDCMock("USDC", "USDC", 6);
        link = new LINKMock("LINK", "LINK", 18);
        usdt = new USDTMock("USDT", "USDT", 6);

        // Deploy router
        router = new LiquidityRouter(
            address(manager),
            address(usdc),
            address(link),
            address(usdt)
        );

        // Mint tokens to user
        usdc.mint(user, USER_BALANCE);
        link.mint(user, USER_LINK_BALANCE);
        usdt.mint(user, USER_BALANCE);

        // Approve router to spend user's tokens
        vm.startPrank(user);
        usdc.approve(address(router), type(uint256).max);
        link.approve(address(router), type(uint256).max);
        usdt.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function _initializePool(address currency0, address currency1) internal {
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
    }

    // ==================== Constructor Tests ====================

    function test_constructor_setsPoolManager() public view {
        assertEq(address(router.poolManager()), address(manager));
    }

    // ==================== AddLiquidity Tests ====================

    function test_addLiquidity_transfersTokensFromUser() public {
        _initializePool(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        uint256 userUSDCBefore = usdc.balanceOf(user);
        uint256 userLINKBefore = link.balanceOf(user);

        vm.prank(user);
        router.addLiquidity(key, INITIAL_USDC, INITIAL_LINK);

        // Verify tokens were transferred from user
        assertEq(usdc.balanceOf(user), userUSDCBefore - INITIAL_USDC);
        assertEq(link.balanceOf(user), userLINKBefore - INITIAL_LINK);
    }

    function test_addLiquidity_revertsWithInsufficientBalance() public {
        _initializePool(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        // Create user with insufficient USDC
        address poorUser = address(0x2);
        usdc.mint(poorUser, INITIAL_USDC - 1);
        link.mint(poorUser, INITIAL_LINK);

        vm.startPrank(poorUser);
        usdc.approve(address(router), type(uint256).max);
        link.approve(address(router), type(uint256).max);
        vm.expectRevert();
        router.addLiquidity(key, INITIAL_USDC, INITIAL_LINK);
        vm.stopPrank();
    }

    function test_addLiquidity_revertsWithInsufficientLINK() public {
        _initializePool(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        // Create user with insufficient LINK
        address poorUser = address(0x2);
        usdc.mint(poorUser, INITIAL_USDC);
        link.mint(poorUser, INITIAL_LINK - 1);

        vm.startPrank(poorUser);
        usdc.approve(address(router), type(uint256).max);
        link.approve(address(router), type(uint256).max);
        vm.expectRevert();
        router.addLiquidity(key, INITIAL_USDC, INITIAL_LINK);
        vm.stopPrank();
    }

    function test_addLiquidity_revertsWithoutApprovalUSDP() public {
        _initializePool(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        address unapprovedUser = address(0x3);
        usdc.mint(unapprovedUser, INITIAL_USDC);
        link.mint(unapprovedUser, INITIAL_LINK);

        vm.startPrank(unapprovedUser);
        link.approve(address(router), type(uint256).max); // Only approve LINK
        vm.expectRevert();
        router.addLiquidity(key, INITIAL_USDC, INITIAL_LINK);
        vm.stopPrank();
    }

    function test_addLiquidity_revertsWithoutApprovalLINK() public {
        _initializePool(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        address unapprovedUser = address(0x3);
        usdc.mint(unapprovedUser, INITIAL_USDC);
        link.mint(unapprovedUser, INITIAL_LINK);

        vm.startPrank(unapprovedUser);
        usdc.approve(address(router), type(uint256).max); // Only approve USDC
        vm.expectRevert();
        router.addLiquidity(key, INITIAL_USDC, INITIAL_LINK);
        vm.stopPrank();
    }

    function test_addLiquidity_withDifferentAmounts() public {
        _initializePool(address(usdc), address(link));
        PoolKey memory key = createTestPoolKey(address(usdc), address(link));

        uint256 customUSDCAmount = 10e6;
        uint256 customLINKAmount = 10e18;

        uint256 userUSDCBefore = usdc.balanceOf(user);
        uint256 userLINKBefore = link.balanceOf(user);

        vm.prank(user);
        router.addLiquidity(key, customUSDCAmount, customLINKAmount);

        assertEq(usdc.balanceOf(user), userUSDCBefore - customUSDCAmount);
        assertEq(link.balanceOf(user), userLINKBefore - customLINKAmount);
    }

    function test_addLiquidity_withUSDTAsSecondCurrency() public {
        _initializePool(address(usdc), address(usdt));
        PoolKey memory key = createTestPoolKey(address(usdc), address(usdt));

        uint256 userUSDCBefore = usdc.balanceOf(user);
        uint256 userUSDTBefore = usdt.balanceOf(user);

        vm.prank(user);
        router.addLiquidity(key, INITIAL_USDC, INITIAL_USDC);

        assertEq(usdc.balanceOf(user), userUSDCBefore - INITIAL_USDC);
        assertEq(usdt.balanceOf(user), userUSDTBefore - INITIAL_USDC);
    }

    // ==================== Helper Functions ====================

    function createTestPoolKey(address currency0, address currency1)
        internal
        pure
        returns (PoolKey memory)
    {
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
