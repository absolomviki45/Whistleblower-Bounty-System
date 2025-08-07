# 🔒 Whistleblower Bounty System

A decentralized smart contract system built on Stacks that enables verified whistleblowers to submit anonymous reports and receive reward tokens for valid submissions.

## 🎯 Features

- **Anonymous Reporting**: Verified whistleblowers can submit reports using cryptographic hashes
- **Reward System**: Earn bounty tokens for validated reports
- **Verification System**: Only verified whistleblowers can participate
- **Validation Process**: Contract owner validates submitted reports
- **Voting Mechanism**: Community voting on report validity
- **Emergency Controls**: Owner can manage funds and rewards

## 🚀 Getting Started

### Prerequisites
- Clarinet CLI installed
- Stacks wallet configured

### Installation
```bash
clarinet new whistleblower-bounty
cd whistleblower-bounty
# Copy the contract file to contracts/ directory
```

## 📋 Usage

### For Contract Owner

#### 1. Verify Whistleblowers 🔐
```clarity
(contract-call? .Whistleblower-Bounty-System verify-whistleblower 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

#### 2. Fund Contract 💰
```clarity
(contract-call? .Whistleblower-Bounty-System fund-contract u5000)
```

#### 3. Validate Reports ✅
```clarity
(contract-call? .Whistleblower-Bounty-System validate-report u1 true)
```

#### 4. Set Reward Amount 🎁
```clarity
(contract-call? .Whistleblower-Bounty-System set-reward-amount u2000)
```

### For Whistleblowers

#### 1. Submit Report 📝
```clarity
(contract-call? .Whistleblower-Bounty-System submit-report 0x1234567890abcdef1234567890abcdef12345678)
```

#### 2. Vote on Reports 🗳️
```clarity
(contract-call? .Whistleblower-Bounty-System vote-on-report u1 true)
```

#### 3. Check Balance 💳
```clarity
(contract-call? .Whistleblower-Bounty-System get-balance tx-sender)
```

### Read-Only Functions

#### Get Report Details 📊
```clarity
(contract-call? .Whistleblower-Bounty-System get-report u1)
```

#### Check Verification Status 🔍
```clarity
(contract-call? .Whistleblower-Bounty-System is-verified-whistleblower tx-sender)
```

#### Get Report Status 📈
```clarity
(contract-call? .Whistleblower-Bounty-System get-report-status u1)
```

## 🏗️ Contract Structure

### Data Storage
- **Reports**: Stores report metadata including hash, status, and rewards
- **Verified Whistleblowers**: Maintains list of authorized reporters
- **Votes**: Tracks community voting on reports
- **Bounty Tokens**: Fungible token for rewards

### Status Flow
1. **pending** → Report submitted, awaiting validation
2. **approved** → Report validated, reward distributed
3. **rejected** → Report deemed invalid, no reward

## 🔧 Configuration

### Default Settings
- Initial token supply: 10,000 tokens
- Default reward amount: 1,000 tokens
- Contract owner: Deployer address

## 🛡️ Security Features

- Only verified whistleblowers can submit reports
- Only contract owner can validate reports
- Emergency withdrawal function for owner
- Duplicate validation prevention
- Balance checks before reward distribution

## 🧪 Testing

Run tests using Clarinet:
```bash
clarinet test
```

## 📄 License

This project is open source and available under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📞 Support

For questions or issues, please open an issue in the GitHub repository.
