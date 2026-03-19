interface IStaker {
    function stake(address beneficiary, uint256 amount) external;

    function redeem() external;
}
