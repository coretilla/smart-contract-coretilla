// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol"; 

// Kontrak untuk MockUSDT
contract MockUSD is ERC20 {
    constructor(address initialOwner) ERC20("Mock USDT", "MUSDT") {
        // Mint 1 miliar token MockUSDT ke deployer (initialOwner)
        // (1,000,000,000 * 10^18)
        _mint(initialOwner, 1000000000 * (10**decimals()));
    }

    /**
     * Fungsi untuk minting token lebih lanjut oleh pemilik.
     * Berguna untuk development dan testing.
     */
    function mint(address to, uint256 amount) public  {
        _mint(to, amount);
    }

    /**
     * Fungsi untuk burn token oleh pemilik atau pemegang token.
     */
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}