// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol"; 

contract MockUSD is ERC20 {
    constructor(address initialOwner) ERC20("Mock USDT", "MUSDT") {
        _mint(initialOwner, 1000000000 * (10**decimals()));
    }

    function mint(address to, uint256 amount) public  {
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}
