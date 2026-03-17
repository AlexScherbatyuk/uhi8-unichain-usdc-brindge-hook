import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract USDTMock is MockERC20 {
    constructor(string memory _name, string memory _symbol, uint8 _decimals) MockERC20(_name, _symbol, _decimals) {}
}
