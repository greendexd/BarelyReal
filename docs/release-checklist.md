# BarelyReal Release Checklist

This checklist is the hard gate for sharing BarelyReal with real users. A build is not
release-ready until every required item is green on both macOS and Windows.

## Release Levels

### Internal Dev Build

For the developer's own machines only.

- [ ] `swift build` succeeds on macOS.
- [ ] `swift run BarelyRealTests` succeeds on macOS.
- [ ] `dotnet build windows/BarelyReal.sln --nologo -warnaserror` succeeds.
- [ ] `windows/scripts/verify.ps1` succeeds on a real Windows machine.
- [ ] Mac app installs with `mac/scripts/install_app.sh`.
- [ ] `codesign --verify --deep --strict /Applications/BarelyReal.app` succeeds.
- [ ] `mac/scripts/diagnose-mac.sh` writes a diagnostics file.
- [ ] `windows/scripts/export-diagnostics.ps1` writes a diagnostics file on Windows.

### Private Alpha

For trusted testers on a known LAN only.

- [ ] All Internal Dev Build checks are green.
- [ ] Pairing is explicit in the UI; no accidental unknown peer control.
- [ ] Clipboard sync supports text, PNG, HTML, and files with clear size limits.
- [ ] Mouse/keyboard handoff works Mac -> Windows and Windows -> Mac.
- [ ] Multi-monitor layout sync works with at least two displays on one side.
- [ ] Emergency return hotkey works while remote mode is active.
- [ ] Lock/sleep/session-change returns input ownership locally.
- [ ] Diagnostics export excludes clipboard payloads, keystrokes, and file bytes.
- [ ] Known broken states are visible in Activity or Home, not silent.

### Public Beta

For users outside the developer's direct control.

- [ ] TLS 1.3 is active for control, clipboard, and file transfer.
- [ ] UDP KM frames are authenticated/encrypted or disabled outside dev mode.
- [ ] 6-digit PIN pairing stores pinned peer identity.
- [ ] mDNS discovery replaces manual IP for normal users.
- [ ] Reconnect/backoff handles peer restart, Wi-Fi sleep, and IP changes.
- [ ] The UI clearly distinguishes trusted, stale, disconnected, and unpaired peers.
- [ ] macOS app is signed with a Developer ID certificate.
- [ ] macOS app is notarized and stapled.
- [ ] Windows installer/app is signed.
- [ ] Windows firewall rules are installed through the app/installer flow.
- [ ] Upgrade/uninstall leaves no orphaned launch or firewall state.

### 1.0 Release

For broad sharing.

- [ ] Security review completed against `docs/security.md`.
- [ ] Hostile-LAN test confirms unauthenticated peers cannot inject input.
- [ ] Clipboard loop prevention works across repeated bidirectional copies.
- [ ] Large file transfer failure is recoverable and does not corrupt clipboard state.
- [ ] p95 KM latency measured and published for Wi-Fi and USB-C.
- [ ] Crash/restart restores local input ownership.
- [ ] Logs rotate and never include sensitive payloads.
- [ ] Release notes include known limitations and supported OS versions.

## Manual Smoke Test

1. Start BarelyReal on Mac and Windows.
2. Pair or connect the two machines.
3. Verify both machines show all local and remote monitors in Devices.
4. Place Windows left of Mac, then right, then above, then below.
5. Cross each matching edge with the cursor.
6. Type into a text field on the remote machine.
7. Copy/paste text, PNG, HTML, and at least one file in both directions.
8. Trigger the emergency-return hotkey while input is remote.
9. Sleep or lock one side and confirm local input returns.
10. Export diagnostics from both apps.

## Sensitive Data Rule

No release artifact, diagnostic bundle, log file, test fixture, or screenshot may include:

- actual keystroke text;
- clipboard payload content;
- file bytes transferred by a user;
- private keys, TLS exporter material, PIN values, or pinned peer secrets.
