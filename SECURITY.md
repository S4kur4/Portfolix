# Security Policy

## Reporting a Vulnerability

Please report security issues privately to the project maintainer before public disclosure. Do not create a public issue containing exploit details, API keys, personal portfolio data, or signing credentials.

## Sensitive Data

Do not commit:

- LLM or Search API keys
- Personal portfolio databases or exported data packages
- Apple signing certificates, `.p12` files, private keys, or notarization credentials
- Provider tokens, cookies, session data, or local `.env` files

## Local-First Boundary

Portfolix does not connect to brokerage accounts. AI analysis uses user-configured providers and may send portfolio data to the configured LLM provider when the user explicitly generates analysis.

## Release Signing

Official release builds should be signed with Developer ID, hardened runtime enabled, notarized by Apple, and verified before uploading to GitHub Releases.
