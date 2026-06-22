# A Privacy-Preserving DAO Model Using NFT Authentication for the Punishment not Reward Blockchain Architecture

Smart contract and empirical data for the Punishment not Reward (PnR) DAO model.
The contracts are deployed and source-verified on **Base mainnet**, and the
repository holds the governance dataset and analysis behind the paper.

## What this is

A DAO governance design that uses reputation-based deterrence instead of token
rewards. The implementation covers:

- A dual NFT framework that separates authentication from private interaction
- Graduated punishment, from a warning through restriction to removal, with conditional identity disclosure on a passed vote
- One-member-one-vote governance rather than token-weighted voting
- An empirical cost study built from real governance transactions on Ethereum, Arbitrum, and Polygon

## Live deployment (Base mainnet, chain ID 8453)

| Contract | Address |
|---|---|
| `PnRDAO` (governance) | [`0x7f09e59FEd0d80be8A093065C60A98B5C6BFd2dD`](https://basescan.org/address/0x7f09e59FEd0d80be8A093065C60A98B5C6BFd2dD) |
| `AuthenticationNFT` (soulbound ERC-721) | [`0x6148F08e317Ee06a2Fac8dAc4232b6f715Df273f`](https://basescan.org/address/0x6148F08e317Ee06a2Fac8dAc4232b6f715Df273f) |
| `PrivateInteractionNFT` (ERC-1155) | [`0x5D67a6F56c86a11fE83265bD5a94835551202262`](https://basescan.org/address/0x5D67a6F56c86a11fE83265bD5a94835551202262) |

The source is verified, so the exact deployed code is readable on
[BaseScan](https://basescan.org/address/0x7f09e59FEd0d80be8A093065C60A98B5C6BFd2dD#code)
and on [Sourcify](https://repo.sourcify.dev/8453/0x7f09e59FEd0d80be8A093065C60A98B5C6BFd2dD).
The two NFT contracts are deployed by the `PnRDAO` constructor; their addresses
are returned by the `authNFT()` and `privNFT()` getters. Full details are in
[deployment/DEPLOYMENTS.md](deployment/DEPLOYMENTS.md).

## Repository layout

```
pnr_dao.sol            Main contract (PnRDAO + the two NFT contracts)
deployment/            Deployment and verification artifacts
  PnRDAO_remix.sol       Remix-ready source (OpenZeppelin imports pinned to 4.9.6)
  PnRDAO_flattened.sol   Flattened single file used for BaseScan verification
  DEPLOYMENTS.md         Live addresses, compiler settings, explorer links
  DEPLOY_BASE_REMIX.md   Step-by-step deploy and on-chain activity guide
On-Chain Data/         Governance dataset (150 transactions) + addresses collected
Analysis/              Python scripts that build the cost figures
paper_bcra/            LaTeX source of the paper
Links.md               Deployment links
```

## Governance dataset

The empirical analysis uses 150 governance transactions collected from established
DAOs, with hashes that can be checked on the public explorers:

- MakerDAO: 25 transactions, $0.89 average per vote
- Compound: 25 transactions, $0.33 average
- Uniswap: 25 transactions, $0.15 average
- Arbitrum DAO: 25 transactions, $0.0061 average
- Polygon (general L2 transactions, used as an L2 cost baseline): 50 transactions, $0.0037 average

The raw data is in [On-Chain Data/](On-Chain%20Data) and the analysis scripts are
in [Analysis/](Analysis). ETH historical price reference:
https://etherscan.io/chart/etherprice

## Deploy it yourself

The contract uses OpenZeppelin 4.x (`Counters`, `security/ReentrancyGuard`), so it
needs OpenZeppelin 4.9.6, not 5.x. The optimizer must be on, otherwise the
unoptimized bytecode exceeds the 24,576-byte contract size limit.

Using Remix:

1. Open [remix.ethereum.org](https://remix.ethereum.org) and paste
   [deployment/PnRDAO_remix.sol](deployment/PnRDAO_remix.sol) (its imports are
   already pinned to `@openzeppelin/contracts@4.9.6`).
2. Compile with Solidity 0.8.19, optimizer enabled (200 runs).
3. Deploy the **PnRDAO** contract (its constructor deploys the two NFT contracts).

The full deploy, verification, and on-chain activity walkthrough is in
[deployment/DEPLOY_BASE_REMIX.md](deployment/DEPLOY_BASE_REMIX.md).

### Basic usage

```solidity
// Owner verifies an identity (DKYC stand-in)
pnrDAO.simulateDKYC(userAddress);

// Member joins with identity and privacy commitments
pnrDAO.joinDAO(identityCommitment, privacyCommitment);

// Open a punishment proposal
pnrDAO.createProposal(targetMember, "behaviour violation",
                      ProposalType.REPUTATION_PENALTY,
                      PunishmentSeverity.WARNING, evidenceRoot);

// Vote (one member, one vote)
pnrDAO.vote(proposalId, true, evidenceProof);

// Create a private service deal (payable)
pnrDAO.createPrivateDeal(seller, "service description", deadline,
                         SERVICE_DEALS, privacyCommitment);
```

## Limitations

This is a research prototype. DKYC is simulated by an owner-set flag rather than a
production identity service, identity disclosure relies on that trusted role rather
than an on-chain zero-knowledge opening, and votes are recorded in the clear. These
are the points the paper is explicit about, and they mark where the design would
need real identity and privacy infrastructure before production use.

## Citation

```bibtex
@article{bayan2024privacy,
  title={A Privacy-Preserving DAO Model Using NFT Authentication for the Punishment not Reward Blockchain Architecture},
  author={Bayan, Talgar and Banach, Richard},
  journal={arXiv preprint arXiv:2405.13156},
  year={2024},
  eprint={2405.13156},
  archivePrefix={arXiv},
  primaryClass={cs.CR},
  doi={10.48550/arXiv.2405.13156}
}
```
