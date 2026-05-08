# BarelyReal

Cross-platform KM (keyboard/mouse) and clipboard sharing between macOS and Windows over Wi-Fi/LAN or USB-C.

A modern alternative to Synergy / Barrier / Universal Control with a focus on:
- Low latency (UDP for KM events, TCP+TLS for control/clipboard/files).
- Native integration on both platforms (Swift + AppKit/SwiftUI on macOS, C#/.NET on Windows; current dev UI is WPF).
- Strong security by default (TLS 1.3 + 6-digit PIN pairing, key pinning).
- USB-C as a first-class transport for zero-network setups.

## Repository layout

```
BarelyReal/
├── protocol/   # BarelyReal Protocol (BRP) wire-format spec
├── mac/        # macOS app (Swift, Xcode/SPM)
├── windows/    # Windows app (C#/.NET 8, WPF dev UI)
└── docs/       # Architecture & security docs
```

See:
- [protocol/BRP-1.0.md](protocol/BRP-1.0.md) — wire-format specification.
- [docs/architecture.md](docs/architecture.md) — system design.
- [docs/security.md](docs/security.md) — threat model & pairing.
- [docs/production-readiness.md](docs/production-readiness.md) — roadmap from dev bridge to shippable product.
- [docs/release-checklist.md](docs/release-checklist.md) — release gates before sharing builds with users.

## Status

🚧 Early development. MVP scope and roadmap in [docs/architecture.md](docs/architecture.md).

Implemented so far:
- BRP frame codecs on macOS + Windows with shared byte fixtures.
- KM payload helpers on macOS + Windows.
- Launchable macOS controller app with KM edge mode, multi-monitor layout editor, scroll speed, permission checks, and clipboard test buttons.
- Mac -> Windows and Windows -> Mac KM dev paths over UDP with edge transition and trusted-peer source filtering.
- Text, PNG, and file clipboard sync over TCP port `24802`.
- Dev control channel on TCP port `24800` for `Hello`, `ScreenAnnounce`, `LayoutSync`, and `KeepAlive`.
- Heartbeat/link-loss detection with optional lock-on-disconnect.
- PIN lockout + pinned-peer identity store scaffold for pairing.
- Wake-on-LAN packet sender.
- Local clipboard history store (JSON MVP, storage API can move to SQLite later).
- Multi-monitor display enumeration and synced virtual layout for macOS + Windows screen groups.
- Branded Cursor Bridge icon for macOS `.app` and Windows WPF app.

## Building

## Run the Current Dev Bridge

This is the current working path. KM still uses raw UDP dev mode with a trusted peer IP filter,
and control/layout sync uses clear TCP dev mode. TLS/PIN security is the next hardening step.

1. On Windows, unzip/copy the project and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File windows/scripts/verify.ps1
   powershell -ExecutionPolicy Bypass -File windows/scripts/allow-firewall.ps1
   dotnet run --project windows/App/BarelyReal.App.csproj
   ```

2. Find the Windows machine IP, for example with `ipconfig`.

3. On Mac, install or launch the app:

   ```sh
   ./mac/scripts/install_app.sh
   open /Applications/BarelyReal.app
   ```

4. Enter the Windows Wi-Fi IP in the Mac app. Both apps exchange all local screens on TCP `24800`.
   The Devices page shows every monitor in one virtual layout.

5. Drag the peer screen group in Devices to the real physical position: left, right, top,
   bottom, or a corner/offset. Moving the cursor across a matching physical edge transfers
   control to the other machine.

The old `BarelyRealKmSmoke` CLI remains useful for smoke tests, but the app UI is now the
preferred controller.

If capture prints no frames on Mac, grant Accessibility permission to the terminal/Codex app in System Settings.

## Diagnostics

Diagnostics must never include clipboard payloads, typed text, transferred file bytes, private keys, or PIN values.

macOS:

```sh
./mac/scripts/diagnose-mac.sh
```

The Mac app also has an **Activity → Export Diagnostics** button that writes a sanitized
diagnostic report to Downloads.

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File windows\scripts\export-diagnostics.ps1
```

### macOS

Builds with Swift 5.9+ on macOS 14+. The Swift Package Manager scaffold works against either
a full Xcode install or just the Command Line Tools.

Install the macOS app locally:

```sh
./mac/scripts/install_app.sh
```

This builds `mac/dist/BarelyReal.app`, signs it ad-hoc for local development, then installs it into
`/Applications/BarelyReal.app` when possible, or `~/Applications/BarelyReal.app` when `/Applications`
is not writable.

Create a zip artifact that can be moved to another Mac:

```sh
./mac/scripts/package_app.sh
```

The artifact is written to `mac/dist/BarelyReal-mac.zip` with a SHA-256 file next to it.
This is a local/dev build, not a notarized public release.

You can also double-click `Install BarelyReal.command` or `Package BarelyReal.command` in the repository root.

```sh
cd mac
swift build                  # builds BarelyRealCore (lib) + BarelyReal (menu-bar app)
swift run BarelyRealTests    # runs the protocol/KM test suite
swift run BarelyReal         # launches the menu-bar app
swift run BarelyRealKmSmoke udp-loopback
swift run BarelyRealKmSmoke capture 10
```

### Windows

Requires the .NET 8 SDK on Windows. The current dev receiver UI is WPF so it can run directly with `dotnet run`;
the final product shell can still move to WinUI/tray once the core path is stable.

```pwsh
cd windows
dotnet build BarelyReal.sln
dotnet run --project Tests   # runs the protocol-codec test suite (mirrors the macOS suite)
dotnet run --project App     # starts the dev receiver UI
powershell -ExecutionPolicy Bypass -File scripts/allow-firewall.ps1
```

The `windows/Tests/` and `mac/Tests/` suites share cross-platform byte fixtures
for KM, control frames, and file bundles. On macOS, `dotnet build windows/BarelyReal.sln`
can catch Windows compile errors if .NET 8 is installed, but the Windows tests/apps must run
on Windows because they target `net8.0-windows` / `Microsoft.WindowsDesktop.App`.

## License

TBD.
