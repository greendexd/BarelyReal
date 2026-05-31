# Security Policy

BarelyReal handles keyboard, mouse, clipboard, and file-transfer data. Please
treat all security reports as sensitive.

## Supported versions

BarelyReal is pre-1.0 and does not currently have supported production
releases. Public source is available for review and early testing, but current
dev builds are not hardened for hostile networks.

## Reporting a vulnerability

Please open a private GitHub security advisory for this repository when
available. If that is not available, create a minimal public issue that says a
security report exists without including exploit details, secrets, payloads,
or personal data.

Include:

- Affected platform and commit SHA.
- Impact and expected attacker position.
- Reproduction steps using sanitized data.
- Whether keystrokes, clipboard payloads, files, pairing secrets, or private
  keys can be exposed or modified.

Do not post real clipboard contents, passwords, tokens, private keys, or
captured input streams in issues, pull requests, logs, screenshots, or
diagnostic bundles.

## Current security status

See [docs/security.md](docs/security.md) for the intended release security
model and [docs/production-readiness.md](docs/production-readiness.md) for the
remaining hardening work. Current dev-mode transports and pairing scaffolding
are documented there and are not a production security boundary.
