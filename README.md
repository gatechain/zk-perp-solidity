# Zk-Perp

## Introduction

### Steps
1. Users deposit stablecoin USDT into the contract.
2. Once the relayer detects the deposit event, it invokes the perpetual contract engine API to process the deposit.
3. After the deposit is completed, users can place orders, cancel orders, and make withdrawals on the perpetual contract platform.
4. The zk calculation service performs calculations and generates zk proofs for transactions such as deposits, withdrawals, order placement, order cancellation, and successful order matching.
5. The generated proofs, along with the corresponding transaction list, are sent to the contract to update the user's state root and withdrawal Merkle Root.
6. Users send withdrawal proofs to the contract to initiate withdrawals.

### Key Functions
1. `function deposit(address user, uint256 amount) public whenNotPaused`
   1. file: interactions/Deposits.sol
   2. users call this method to deposit funds to a specified user
   3. emit LogDeposit event
2. zk calculation service sends proof
   1. file: perp/Perp.sol
      ```
      function forgeBatch(
      uint256 newRoots,
      bytes calldata txsData,
      bytes calldata newOrders,
      bytes calldata newAccounts,
      uint8 verifierIdx,
      uint256[8] calldata proof
      ) external virtual whenNotPaused {
      ```
3. user withdraws
   1. file: perp/Perp.sol
   2. ```
      function withdrawMerkleProof(
      uint192 amount,
      uint256 babyPubKey,
      uint32 numExitRoot,
      uint256[] memory siblings,
      uint48 idx
      ) external whenNotPaused
      ```

### Run tests
1. Install foundry: `https://book.getfoundry.sh/getting-started/installation`
2. Install dependencies:
   1. `forge install foundry-rs/forge-std  --no-git`
   2. `npm install`
4. Run tests: `forge test`

## Audit Details
- Files Requiring Audit
  - contracts/Perpetual.sol
  - contracts/interactions/TokenAssetData.sol
  - contracts/interactions/Deposits.sol
  - contracts/interfaces/MTokenTransfers.sol
  - contracts/components/TokenTransfers.sol
  - contracts/components/MainStorage.sol
  - contracts/perp/Perp.sol
  - contracts/perp/interfaces/VerifierRollupInterface.sol
  - contracts/perp/lib/PerpHelpers.sol
- Files Exempt from Audit
  - contracts/libraries/Common.sol
  - contracts/upgradability/Timelock.sol
  - contracts/PerpetualProxy.sol
  - contracts/perp/test/VerifierRollupHelper.sol
  - contracts/components/Initializable.sol
  - contracts/components/Ownable.sol
  - contracts/components/Pausable.sol
