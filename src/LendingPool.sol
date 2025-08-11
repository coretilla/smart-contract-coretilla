// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";

contract LendingPool is Ownable {
    IERC20 public immutable mockBTCToken;
    IERC20 public immutable mockUSDTToken;

    // Harga MockBTC dalam MockUSDT (dengan asumsi keduanya 18 desimal)
    // Misal: 1 MockBTC = 50,000 MockUSDT -> btcPriceInUSDT = 50000 * 10**18
    uint256 public btcPriceInUSDT; 
    // Loan To Value Ratio dalam persen, misal 50 untuk 50%
    uint256 public loanToValueRatioPercent; 

    mapping(address => uint256) public collateralBalancesBTC; // Jumlah MockBTC yang dijaminkan
    mapping(address => uint256) public borrowedBalancesUSDT;  // Jumlah MockUSDT yang dipinjam

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
        uint256 _initialBTCPriceInUSDT, // Misal: 50000 * 10**18
        uint256 _initialLTVPercent,     // Misal: 50 (untuk 50%)
        address initialOwner
    ) Ownable(initialOwner) {
        mockBTCToken = IERC20(_mockBTCTokenAddress);
        mockUSDTToken = IERC20(_mockUSDTTokenAddress);
        btcPriceInUSDT = _initialBTCPriceInUSDT;
        loanToValueRatioPercent = _initialLTVPercent;
        require(_initialLTVPercent > 0 && _initialLTVPercent <= 80, "LTV must be between 1-80%"); // Batas aman
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
     * @dev Admin bisa mengirimkan MockUSDT ke kontrak ini agar bisa dipinjamkan.
     * Panggil fungsi 'approve' di kontrak MockUSDT dari akun admin dulu.
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

        // Hitung nilai jaminan dalam USDT
        // (collateralBTC * btcPriceInUSDT) / 10**18 (karena harga juga punya 18 desimal presisi)
        uint256 collateralValueUSDT = (collateralBTC * btcPriceInUSDT) / 1e18; 
        
        // Hitung maksimal USDT yang bisa dipinjam
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

        // Untuk MVP, bunga diabaikan. Jika ada bunga, _amountUSDTToRepay harus mencakup pokok + bunga.
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
            // Jika masih ada pinjaman, pastikan jaminan sisa masih mencukupi
            uint256 remainingCollateralValueUSDT = (remainingCollateralBTC * (btcPriceInUSDT)) / (1e18);
            uint256 requiredCollateralValueUSDT = currentBorrowedUSDT * (100) / (loanToValueRatioPercent); // Kebalikan dari LTV
            require(remainingCollateralValueUSDT >= requiredCollateralValueUSDT, "LendingPool: Insufficient collateral after withdrawal for existing loan");
        }

        collateralBalancesBTC[msg.sender] = remainingCollateralBTC;
        mockBTCToken.transfer(msg.sender, _amountBTCToWithdraw);
        
        emit CollateralWithdrawn(msg.sender, _amountBTCToWithdraw);
    }

    // --- Liquidation (MVP Sederhana) ---
    /**
     * @dev Likuidasi posisi peminjam jika dibawah jaminan.
     * Untuk MVP, hanya owner yang bisa melikuidasi.
     * Liquidator (owner) akan membayar utang USDT peminjam ke pool,
     * dan mendapatkan jaminan BTC peminjam dengan diskon (atau semua jaminan untuk MVP).
     */
    function liquidatePosition(address _borrower) external onlyOwner {
        uint256 collateralBTC = collateralBalancesBTC[_borrower];
        uint256 borrowedUSDT = borrowedBalancesUSDT[_borrower];

        require(collateralBTC > 0 && borrowedUSDT > 0, "LendingPool: No position to liquidate or no debt");

        uint256 collateralValueUSDT = (collateralBTC * (btcPriceInUSDT)) / (1e18);
        
        // Kondisi likuidasi: jika nilai jaminan jatuh di bawah nilai hutang (atau batas LTV tertentu)
        // Untuk MVP, kita buat sederhana: jika nilai jaminan < nilai hutang (artinya LTV > 100%)
        require(collateralValueUSDT < borrowedUSDT, "LendingPool: Position is not undercollateralized enough for liquidation");

        // Logika likuidasi MVP: Owner (sebagai liquidator) "membayar" utang USDT peminjam (secara internal)
        // dan mengambil semua jaminan BTC peminjam.
        // Pool menerima kembali USDT (sebenarnya hanya pembukuan karena Owner yg trigger)
        // atau lebih baik: Owner mengirim USDT ke pool untuk melunasi hutang peminjam, lalu Owner terima BTC
        
        // Untuk MVP yang sangat sederhana: Hapus utang peminjam, sita jaminannya untuk kontrak.
        uint256 seizedCollateral = collateralBTC; // Ambil semua jaminan
        uint256 debtCleared = borrowedUSDT;

        collateralBalancesBTC[_borrower] = 0;
        borrowedBalancesUSDT[_borrower] = 0;
        
        // Jaminan yang disita menjadi milik kontrak, bisa ditarik oleh owner nanti
        // atau digunakan untuk menutupi kerugian pool.
        // mockBTCToken.transfer(owner(), seizedCollateral); // Opsi: langsung ke owner

        emit Liquidated(_borrower, msg.sender, seizedCollateral, debtCleared);
    }

    // Helper untuk melihat kesehatan akun (bisa dipanggil dari frontend)
    function getAccountHealth(address _user) external view returns (uint256 healthFactor) {
        uint256 collateralBTC = collateralBalancesBTC[_user];
        uint256 borrowedUSDT = borrowedBalancesUSDT[_user];

        if (borrowedUSDT == 0) {
            return type(uint256).max; // Sehat jika tidak ada pinjaman
        }
        
        uint256 collateralValueUSDT = (collateralBTC * btcPriceInUSDT) / 1e18;
        // Health Factor = (Collateral Value * LTV) / Borrowed Value
        // Jika HF < 100 (atau 1e18), bisa dilikuidasi
        healthFactor = (collateralValueUSDT * loanToValueRatioPercent * 1e18) / (100 * borrowedUSDT);
        return healthFactor;
    }
}