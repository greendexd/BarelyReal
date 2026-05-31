# Contributing to BarelyReal

BarelyReal is an early macOS + Windows KM and clipboard sharing project. The
most useful contributions right now are small, verifiable fixes that improve
protocol correctness, security hardening, platform reliability, diagnostics,
or documentation.

## Ground rules

- Keep changes focused and easy to review.
- Do not commit generated app bundles, packages, logs, local databases, private
  keys, certificates, provisioning profiles, screenshots with personal data, or
  clipboard/input captures.
- Treat keyboard, mouse, clipboard, file-transfer, and pairing code as
  security-sensitive.
- Keep diagnostics sanitized. They must not contain keystrokes, clipboard
  payloads, file bytes, PIN values, private keys, or access tokens.
- Update the relevant docs when changing protocol behavior, ports, pairing,
  trust storage, clipboard/file handling, or release packaging.

## Local checks

Run the checks for the area you changed before opening a pull request.

macOS:

```sh
cd mac
swift build
swift run BarelyRealTests
swift run BarelyRealKmSmoke udp-loopback
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File windows/scripts/verify.ps1
```

Optional Mac-side Windows compile check when .NET 8 is installed:

```sh
dotnet build windows/BarelyReal.sln --nologo -warnaserror
```

## Pull requests

Include:

- What changed and why.
- Which platform(s) you tested.
- The exact commands you ran.
- Any security, privacy, or compatibility tradeoffs.

Large rewrites should start as an issue or draft PR so the direction can be
reviewed before implementation work goes deep.
