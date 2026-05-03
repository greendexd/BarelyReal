# BarelyReal — Security model

## Threat model

BarelyReal handles **highly sensitive** input streams: every keystroke (including passwords), every clipboard payload (including secrets), and arbitrary file transfers. We assume:

- The local network may be hostile (coffee-shop Wi-Fi, shared hotel SSID, untrusted office VLAN).
- An attacker on the same broadcast domain can observe mDNS, see the service exists, and attempt to connect.
- An attacker can attempt MITM on the TLS handshake.
- An attacker cannot run code as the user on either machine. (If they can, all bets are off.)

Out of scope:
- Side-channel attacks (timing, power).
- Physical attacker with the unlocked machine.

## Defenses

### Transport encryption

All control / clipboard / file traffic uses **TLS 1.3** with platform-provided stacks:
- macOS: `Network.framework` (Apple's TLS, ATS-grade).
- Windows: `SslStream` over `Schannel`.

KM events go over UDP and use **ChaCha20-Poly1305 AEAD** with keys derived from the TLS exporter (RFC 5705), so the same handshake authenticates both channels. No plain-text fallback is permitted.

### Pairing (TOFU + PIN)

First connection between two devices:

1. Both sides generate per-device long-lived ed25519 keys at install time, stored in the platform secret store (Keychain / DPAPI). The TLS cert is self-signed and bound to this key.
2. On a new pair, TLS 1.3 ECDHE handshake completes. Both sides extract a 6-digit short authentication string from the TLS exporter (see [BRP-1.0.md](../protocol/BRP-1.0.md) § Pairing).
3. Initiator's UI displays the 6 digits; the user types them on the responder's UI. Match → both sides pin the SubjectPublicKeyInfo SHA-256 of the peer's certificate.
4. Future connections to the same peer require an exact pin match. Mismatch is treated as MITM, connection refused, user notified.

### PIN brute-force protection

- 6-digit PIN → 1,000,000 possibilities.
- Wrong attempt counter is per-peer-key.
- 5 wrong attempts → 60 s lockout. After 25 total wrong attempts → require user to manually re-enable pairing in settings.

### Key storage

Pinned peer SPKI hashes and our own ed25519 private key live in:
- **macOS**: Keychain, accessible only to the BarelyReal app's signing identity (`kSecAttrAccessibleWhenUnlocked`).
- **Windows**: DPAPI under user scope, file in `%LocalAppData%\BarelyReal\trust.dat`.

Never written to plain-text files, never logged.

### Privilege

- macOS app needs **Accessibility** and **Input Monitoring** TCC entitlements (granted by user in System Settings → Privacy & Security). No root required.
- Windows app uses low-level hooks; runs as a normal user. **UAC-elevated mode** is opt-in (toggle in settings) — only required to inject input into elevated windows (Task Manager, UAC prompt). When elevated, we display a clear indicator.

### Lock on disconnect (opt-in)

If KM heartbeat is lost while a peer was the active server, the receiving side optionally locks its screen. Off by default — too disruptive for flaky Wi-Fi — but recommended.

### Logging hygiene

- Logs **never** contain keystroke content, clipboard payloads, or file bytes.
- Logs may contain: connection states, frame counts, latency stats, error codes.
- Log files rotate at 10 MB / 5 files.

## Non-goals

- Anonymity. Devices announce themselves on mDNS by user-chosen name.
- Hiding from the local network. We are an LAN service.
- Resistance to a compromised local machine. If your kernel is rooted, BarelyReal cannot save you.

## Audit checklist (pre-1.0 release)

- [ ] No `OPENSSL_*` or unsupported-cipher fallbacks.
- [ ] TLS pinning bypass attempts produce a hard fail and a user notification.
- [ ] PIN lockout enforced even across app restarts (counter persisted).
- [ ] Memory containing PINs and clipboard payloads is zeroed on free where the language allows (`sodium_memzero` / `CryptographicBuffer.Clear`).
- [ ] Static analysis: `cargo audit` equivalents — Swift `swift audit`, .NET `dotnet list package --vulnerable`.
- [ ] Penetration test on a hostile-Wi-Fi simulation.
