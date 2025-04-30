
# Hodl Wallet

A simple Bitcoin CLI wallet built with Ruby.  
Supports key generation, balance checking, and transaction sending via the Bitcoin(Signet) blockchain.

---

## 🔧 Getting Started

### Prerequisites

- Ruby (Tested with Ruby 3.2.2)
- Docker (Optional, if you plan to run the wallet via Docker)

### 1. Clone the repository

```bash
git clone https://github.com/ipopovvv/hodl_wallet.git
cd hodl_wallet
```

### 2. Add environment variables

Create a `.env` file in the project root using `.env.sample` as a reference:

```bash
cp .env.sample .env
```

Fill in your API keys or configuration values as needed.

### 3. Install dependencies

Ensure you have Ruby installed (e.g., via rbenv or rvm), then run:

```bash
bundle install
```

### 4. Run the script

To launch the interactive CLI:

```bash
ruby script.rb
```

---

## 🐳 Docker (optional)

If you prefer to run the wallet via Docker, follow these steps.

### Build the image:

```bash
docker build -t hodl_wallet .
```

### Run the script inside a container:

```bash
docker run -it --rm hodl_wallet
```

---

## 🛠 Features

- Generate new Bitcoin wallets (WIF format)
- Check wallet balances
- Send BTC transactions
- Simple modular architecture

---

## 🚧 Roadmap / Future Plans

1. Add RSpec tests and achieve **100% coverage**
2. Integrate `VCR` to mock external API requests
3. Add support for testnet/mainnet switching
4. Add support for legacy (P2PKH) and SegWit (P2WPKH) address generation, allowing users to choose the desired address format based on compatibility and transaction fee optimization.
