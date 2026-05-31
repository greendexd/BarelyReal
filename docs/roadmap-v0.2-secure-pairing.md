# v0.2 Secure Pairing Roadmap

Goal: replace the current dev trust path with a secure, testable pairing and
transport baseline that can support broader alpha testing.

## Scope

- Implement TLS 1.3 control sessions on macOS and Windows.
- Bind TLS identity to durable per-device keys.
- Derive the 6-digit pairing code from TLS exporter material.
- Persist pinned peer public-key hashes on both platforms.
- Reject changed peer keys with a visible error.
- Persist PIN lockout state across app restarts.
- Derive UDP KM encryption keys from the paired TLS session.
- Replace temporary dev HMAC mode with exporter-derived authenticated encryption for release builds.
- Keep dev-mode plaintext transport behind explicit developer switches only.
- Add cross-platform tests for pairing, lockout, replay rejection, and peer-key mismatch behavior.

## Release Criteria

- A fresh Mac/Windows pair succeeds through discovery and manual IP fallback.
- Existing paired devices reconnect without re-pairing.
- A changed peer key fails closed and explains the risk to the user.
- Captured LAN traffic does not include plaintext keystrokes, clipboard payloads, file bytes, or PIN values.
- Diagnostics remain sanitized and exclude sensitive payloads.
- Real Windows and macOS runtime smoke tests are completed before the release is published.

## Out of Scope

- Public installer signing and notarization.
- Multi-peer mesh routing.
- Cloud relay transport.
- Production telemetry.
