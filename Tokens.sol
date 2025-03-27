// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract ProfiCoin is ERC20("ProfiCoin", "PROFI") {
    constructor(address tom, address ben, address rick, address jack){
        _mint(tom, 25000);
        _mint(ben, 25000);
        _mint(rick, 25000);
        _mint(jack, 25000);
    }

    function decimals() public override view virtual returns (uint8) {
        return 12;
    }

   function price() public pure returns(uint) {
        return 2000000 wei;
    }
}

contract RTKCoin is ERC20("RTKCoin", "RTK") {
    constructor(address tom, address ben, address rick, address jack){
        _mint(tom, 50000);
        _mint(ben, 50000);
        _mint(rick, 50000);
        _mint(jack, 50000);
    }

    function decimals() public override view virtual returns (uint8) {
        return 12;
    }

   function price() public pure returns(uint) {
        return 1000000 wei;
    }

}