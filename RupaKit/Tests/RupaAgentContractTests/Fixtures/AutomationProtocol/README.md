# Automation Protocol Fixtures

These fixtures are hand-authored JSON envelopes for non-Swift clients.

| Directory | Contract |
|---|---|
| `requests` | One canonical request fixture per public automation method. |
| `responses/success` | Representative success response envelopes. |
| `responses/error` | Representative error response envelopes. |
| `invalid` | Envelopes that must be rejected by the protocol decoder. |

The Swift test runner decodes every JSON file in this directory tree without constructing payloads through Swift encoders first.

