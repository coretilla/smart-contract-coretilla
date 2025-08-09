# 🧠 Smart Contract – Coretilla

**Coretilla** is a **Bitcoin Neobank** — your digital bank for the Bitcoin economy.  
This repository contains the **Coretilla Smart Contracts** that power our decentralized financial services, deployed on the **Core Blockchain Mainnet**.

Our mission is to bridge Bitcoin with modern DeFi infrastructure, enabling fast, secure, and user-friendly financial tools.

---

## 📦 Tech Stack
- **Foundry** – High-performance Ethereum development toolkit (Rust-based)  
- **Solidity** – Smart contract programming language  
- **Core Blockchain** – EVM-compatible network for Bitcoin economy applications (Mainnet)  

---

## 🔧 Foundry Toolkit

Foundry includes:

- **Forge** – Ethereum testing framework (like Truffle, Hardhat, DappTools)  
- **Cast** – Command-line tool to interact with smart contracts, send transactions, and query blockchain data  
- **Anvil** – Local Ethereum-compatible node for rapid testing  
- **Chisel** – High-speed Solidity REPL for prototyping and debugging  

📚 **Documentation:** [Foundry Book](https://book.getfoundry.sh/)

---

## 🚀 Development Workflow

### 1️⃣ Build Contracts
```bash
forge build
```

### 2️⃣ Run Tests
```bash
forge test
```

### 3️⃣ Format Code
```bash
forge fmt
```

### 4️⃣ Gas Snapshot
```bash
forge snapshot
```

### 5️⃣ Start Local Node
```bash
anvil
```

### 6️⃣ Deploy Contract
```bash
forge script script/Counter.s.sol:CounterScript \
  --rpc-url <your_rpc_url> \
  --private-key <your_private_key>
```

### 7️⃣ Interact via Cast
```bash
cast <subcommand>
```

---

## 🌐 Core Blockchain – Mainnet Contract Addresses

| Contract        | Address                                                                 | Explorer Link |
|-----------------|-------------------------------------------------------------------------|---------------|
| **MockBTC**     | `0x4dABf45C8cF333Ef1e874c3FDFC3C86799af80c8` | [View in Code Explorer](https://scan.coredao.org/address/0x4dABf45C8cF333Ef1e874c3FDFC3C86799af80c8#code) |
| **MockUSD**     | `0x29AFB3d2448ddaa0e039536002234a90aF1e4f31` | [View in Code Explorer](https://scan.coredao.org/address/0x29AFB3d2448ddaa0e039536002234a90aF1e4f31#code) |
| **LendingPool** | `0x3EF7d600DB474F1a544602Bd7dA33c53d98B7B1b` | [View in Code Explorer](https://scan.coredao.org/address/0x3EF7d600DB474F1a544602Bd7dA33c53d98B7B1b#code) |
| **StakingVault**| `0x478AE04E752e47c5b1F597101CeF74f01F0386e6` | [View in Code Explorer](https://scan.test2.btcs.network/address/0x478AE04E752e47c5b1F597101CeF74f01F0386e6#code) |

---

## 💡 About Coretilla
Coretilla combines the **trust and stability of Bitcoin** with the **innovation of decentralized finance**, offering services like:
- Bitcoin-backed lending
- Stablecoin integration
- Yield and staking vaults
- Seamless digital banking experience

## 📜 License
MIT License – You are free to use, modify, and distribute this code.
