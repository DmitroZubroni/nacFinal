// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20, ERC20Votes, EIP712, IVotes } from "./ERC20.sol";

contract ProfiCoin is ERC20Votes {
    constructor(address tom, address ben, address rick, address jack)
     ERC20("ProfiCoin", "Profi") EIP712("ProfiCoin", "1") {
        _mint(tom, 25_000 * 10 ** decimals());
        _mint(ben, 25000 * 10 ** decimals());
        _mint(rick, 25000 * 10 ** decimals());
        _mint(jack, 25000 * 10 ** decimals());
    }


    function transfer(address from, address to, uint amount) external {
        _transfer(from, to, amount);
    }

    function decimals() public override view virtual returns (uint8) {
        return 12;
    }

    function mint(address from, uint amount) external {
        _mint(from, amount);
    }

    function burn(address from, uint amount) external {
        _burn(from, amount);
    }

    function delegate(address account, address delegatee) external   {
        _delegate(account,delegatee);
    }
}

contract RTKCoin is ERC20Votes {
    constructor()
     ERC20("RTKCoin", "RTK") EIP712("RTKCoin", "1") {
     }
    
    function transfer(address from, address to, uint amount) external {
        _transfer(from, to, amount);
    }

    function decimals() public override view virtual returns (uint8) {
        return 12;
    }

   function price() public pure returns(uint) {
        return 1000000 wei;
    }

    function mint(address from, uint amount) external {
        _mint(from, amount);
    }

    function burn(address from, uint amount) external {
        _burn(from, amount);
    }

    function delegate(address account, address delegatee) external   {
        _delegate(account,delegatee);
    }
}