# Third-Party Notices

This file records third-party components that may be used by Portfolix or bundled in release builds.

## AKShare

- Project: AKShare
- Homepage: https://github.com/akfamily/akshare
- Package metadata observed locally: `akshare==1.18.64`, `License: MIT`
- Purpose: optional local market-data helper for stocks and funds

AKShare is licensed under the MIT License. MIT permits use, copy, modification, publication, distribution, sublicensing, and sale, provided the copyright notice and permission notice are included.

If a release build bundles AKShare and its Python dependency tree, the release process must include the license files for AKShare and all transitive Python dependencies in the distributed app or DMG.

## Data Providers

Portfolix may query public market-data sources through AKShare, OKX public endpoints, or user-configured search/LLM providers. The availability, latency, and licensing of upstream data are controlled by the respective providers. Portfolix does not claim ownership of upstream market data.
