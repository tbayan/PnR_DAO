# PnR DAO Implementation

Smart contract implementation of the Punishment not Reward Decentralized Autonomous Organization model from PhD research on blockchain governance.

## Overview

This contract implements a novel DAO governance mechanism that uses reputation-based deterrence instead of token-based rewards. Key features include:

- **Soulbound Authentication NFTs** - Non-transferable membership tokens
- **Democratic Punishment Mechanisms** - Community-driven removal proposals  
- **Private Deal System** - Confidential transactions with dispute resolution
- **Reputation Management** - Dynamic scoring based on behavior

## Quick Deploy

### Using Remix IDE
1. Go to [remix.ethereum.org](https://remix.ethereum.org)
2. Create new file and paste the contract code
3. Install OpenZeppelin: `@openzeppelin/contracts`
4. Compile with Solidity 0.8.19+
5. Deploy to testnet (Polygon Mumbai recommended)

### Basic Usage
```solidity
// 1. Simulate identity verification
pnrDAO.simulateDKYC(userAddress);

// 2. Join DAO with identity commitment
pnrDAO.joinDAO(keccak256("identity_hash"));

// 3. Create removal proposal
pnrDAO.createRemovalProposal(badActor, "reason");

// 4. Vote on proposals
pnrDAO.vote(proposalId, true);
```

## Architecture

```
PnRDAO.sol
├── AuthenticationNFT (soulbound membership)
├── PrivateInteractionNFT (private deals)
└── Governance (voting & punishment)
```

## Research Context

This implementation demonstrates the practical feasibility of the PnR paradigm described in:

**Chapter 5**: "A Privacy-Preserving DAO Model Using NFT Authentication for the Punishment not Reward Blockchain Architecture"

The mathematical governance framework implements:
- Equation 5.1: `Loss_reputation >> Gain_cheating`
- Equation 5.4-5.5: Quorum-based voting mechanisms

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

## Status

🔬 **Research Prototype** - For academic demonstration and testing purposes.

## Contact

**Research Questions**: [your.email@university.edu]  
**Issues**: Use GitHub Issues for technical problems
