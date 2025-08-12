// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";

contract LendingPool is Ownable {
    IERC20 public immutable mockBTCToken;
    IERC20 public immutable mockUSDTToken;

    // MockBTC price in MockUSDT (assuming both have 18 decimals)
    // Example: 1 MockBTC = 50,000 MockUSDT -> btcPriceInUSDT = 50000 * 10**18
    uint256 public btcPriceInUSDT; 
    // Loan To Value Ratio in percent, e.g., 50 for 50%
    uint256 public loanToValueRatioPercent; 

    mapping(address => uint256) public collateralBalancesBTC; // Amount of MockBTC pledged as collateral
    mapping(address => uint256) public borrowedBalancesUSDT;  // Amount of MockUSDT borrowed

    event CollateralDeposited(address indexed user, uint256 btcAmount);
    event CollateralWithdrawn(address indexed user, uint256 btcAmount);
    event LoanTaken(address indexed user, uint256 usdtAmount);
    event LoanRepaid(address indexed user, uint256 usdtAmount);
    event PriceUpdated(uint256 newPrice);
    event LTVUpdated(uint256 newLTV);
    event Liquidated(address indexed borrower, address indexed liquidator, uint256 seizedCollateral, uint256 debtRepaid);

    constructor(
        address _mockBTCTokenAddress,
        address _mockUSDTTokenAddress,
        uint256 _initialBTCPriceInUSDT, // Example: 50000 * 10**18
        uint256 _initialLTVPercent,     // Example: 50 (for 50%)
        address initialOwner
    ) Ownable(initialOwner) {
        mockBTCToken = IERC20(_mockBTCTokenAddress);
        mockUSDTToken = IERC20(_mockUSDTTokenAddress);
        btcPriceInUSDT = _initialBTCPriceInUSDT;
        loanToValueRatioPercent = _initialLTVPercent;
        require(_initialLTVPercent > 0 && _initialLTVPercent <= 80, "LTV must be between 1-80%"); // Safety limit
    }

    // --- Admin Functions ---
    function setBTCPrice(uint256 _newPrice) external onlyOwner {
        btcPriceInUSDT = _newPrice;
        emit PriceUpdated(_newPrice);
    }

    function setLoanToValueRatio(uint256 _newLTVPercent) external onlyOwner {
        require(_newLTVPercent > 0 && _newLTVPercent <= 80, "LTV must be between 1-80%");
        loanToValueRatioPercent = _newLTVPercent;
        emit LTVUpdated(_newLTVPercent);
    }

    /**
     * @dev Admin can send MockUSDT to this contract so it can be lent out.
     * Call the 'approve' function on the MockUSDT contract from the admin account first.
     */
    function fundPool(uint256 _amountUSDT) external onlyOwner {
        mockUSDTToken.transferFrom(msg.sender, address(this), _amountUSDT);
    }

    // --- User Functions ---
    function depositCollateral(uint256 _amountBTC) external {
        require(_amountBTC > 0, "LendingPool: Amount must be > 0");
        mockBTCToken.transferFrom(msg.sender, address(this), _amountBTC);
        collateralBalancesBTC[msg.sender] = collateralBalancesBTC[msg.sender] + (_amountBTC);
        emit CollateralDeposited(msg.sender, _amountBTC);
    }

    function borrowUSDT(uint256 _amountUSDTToBorrow) external {
        require(_amountUSDTToBorrow > 0, "LendingPool: Amount must be > 0");
        
        uint256 collateralBTC = collateralBalancesBTC[msg.sender];
        require(collateralBTC > 0, "LendingPool: No collateral deposited");

        // Calculate collateral value in USDT
        // (collateralBTC * btcPriceInUSDT) / 10**18 (because price also has 18 decimal precision)
        uint256 collateralValueUSDT = (collateralBTC * btcPriceInUSDT) / 1e18; 
        
        // Calculate maximum USDT borrowable
        uint256 maxBorrowableUSDT = (collateralValueUSDT * loanToValueRatioPercent) / (100);
        
        uint256 currentBorrowedUSDT = borrowedBalancesUSDT[msg.sender];
        require(currentBorrowedUSDT + (_amountUSDTToBorrow) <= maxBorrowableUSDT, "LendingPool: Borrow amount exceeds LTV");
        
        require(mockUSDTToken.balanceOf(address(this)) >= _amountUSDTToBorrow, "LendingPool: Insufficient USDT in pool");

        borrowedBalancesUSDT[msg.sender] = currentBorrowedUSDT + (_amountUSDTToBorrow);
        mockUSDTToken.transfer(msg.sender, _amountUSDTToBorrow);
        
        emit LoanTaken(msg.sender, _amountUSDTToBorrow);
    }

    function repayUSDT(uint256 _amountUSDTToRepay) external {
        require(_amountUSDTToRepay > 0, "LendingPool: Amount must be > 0");
        uint256 currentBorrowed = borrowedBalancesUSDT[msg.sender];
        require(_amountUSDTToRepay <= currentBorrowed, "LendingPool: Repay amount exceeds borrowed amount");

        // For MVP, interest is ignored. If there is interest, _amountUSDTToRepay should include principal + interest.
        mockUSDTToken.transferFrom(msg.sender, address(this), _amountUSDTToRepay);
        borrowedBalancesUSDT[msg.sender] = currentBorrowed - _amountUSDTToRepay;
        
        emit LoanRepaid(msg.sender, _amountUSDTToRepay);
    }

    function withdrawCollateral(uint256 _amountBTCToWithdraw) external {
        require(_amountBTCToWithdraw > 0, "LendingPool: Amount must be > 0");
        uint256 currentCollateralBTC = collateralBalancesBTC[msg.sender];
        require(_amountBTCToWithdraw <= currentCollateralBTC, "LendingPool: Withdraw amount exceeds collateral balance");

        uint256 remainingCollateralBTC = currentCollateralBTC - _amountBTCToWithdraw;
        uint256 currentBorrowedUSDT = borrowedBalancesUSDT[msg.sender];

        if (currentBorrowedUSDT > 0) {
            // If there is still a loan, ensure the remaining collateral is sufficient
            uint256 remainingCollateralValueUSDT = (remainingCollateralBTC * (btcPriceInUSDT)) / (1e18);
            uint256 requiredCollateralValueUSDT = currentBorrowedUSDT * (100) / (loanToValueRatioPercent); // Reverse of LTV
            require(remainingCollateralValueUSDT >= requiredCollateralValueUSDT, "LendingPool: Insufficient collateral after withdrawal for existing loan");
        }

        collateralBalancesBTC[msg.sender] = remainingCollateralBTC;
        mockBTCToken.transfer(msg.sender, _amountBTCToWithdraw);
        
        emit CollateralWithdrawn(msg.sender, _amountBTCToWithdraw);
    }

    // --- Liquidation (Simple MVP) ---
    /**
     * @dev Liquidate borrower's position if undercollateralized.
     * For MVP, only the owner can liquidate.
     * The liquidator (owner) will repay the borrower's USDT debt to the pool
     * and receive the borrower's BTC collateral at a discount (or all collateral for MVP).
     */
    function liquidatePosition(address _borrower) external onlyOwner {
        uint256 collateralBTC = collateralBalancesBTC[_borrower];
        uint256 borrowedUSDT = borrowedBalancesUSDT[_borrower];

        require(collateralBTC > 0 && borrowedUSDT > 0, "LendingPool: No position to liquidate or no debt");

        uint256 collateralValueUSDT = (collateralBTC * (btcPriceInUSDT)) / (1e18);
        
        // Liquidation condition: if collateral value falls below the debt value (or certain LTV threshold)
        // For MVP, keep it simple: if collateral value < debt value (meaning LTV > 100%)
        require(collateralValueUSDT < borrowedUSDT, "LendingPool: Position is not undercollateralized enough for liquidation");

        // MVP liquidation logic: Owner (as liquidator) "repays" the borrower's USDT debt (internally)
        // and seizes all the borrower's BTC collateral.
        // The pool regains USDT (accounting-wise since Owner triggers it)
        // or better: Owner sends USDT to pool to repay borrower's debt, then Owner receives BTC
        
        // For a very simple MVP: Clear borrower's debt and seize all collateral for the contract.
        uint256 seizedCollateral = collateralBTC; // Seize all collateral
        uint256 debtCleared = borrowedUSDT;

        collateralBalancesBTC[_borrower] = 0;
        borrowedBalancesUSDT[_borrower] = 0;
        
        // The seized collateral belongs to the contract, can be withdrawn by the owner later
        // or used to cover pool losses.
        // mockBTCToken.transfer(owner(), seizedCollateral); // Option: send directly to owner

        emit Liquidated(_borrower, msg.sender, seizedCollateral, debtCleared);
    }

    // Helper to check account health (can be called from frontend)
    function getAccountHealth(address _user) external view returns (uint256 healthFactor) {
        uint256 collateralBTC = collateralBalancesBTC[_user];
        uint256 borrowedUSDT = borrowedBalancesUSDT[_user];

        if (borrowedUSDT == 0) {
            return type(uint256).max; // Healthy if no debt
        }
        
        uint256 collateralValueUSDT = (collateralBTC * btcPriceInUSDT) / 1e18;
        // Health Factor = (Collateral Value * LTV) / Borrowed Value
        // If HF < 100 (or 1e18), can be liquidated
        healthFactor = (collateralValueUSDT * loanToValueRatioPercent * 1e18) / (100 * borrowedUSDT);
        return healthFactor;
    }
}
