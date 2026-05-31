# Windows Release Test Checklist

Use this checklist on a real Windows x64 machine before promoting an alpha
archive from "cross-published" to "runtime verified".

## Setup

- Download `BarelyReal-win-x64.zip` from the latest GitHub release.
- Verify the `.sha256` checksum.
- Extract the archive to a normal user-writable folder.
- Confirm Windows SmartScreen behavior and record the exact prompt text.

## App Launch

- Launch `BarelyReal.App.exe`.
- Launch `Launch BarelyReal.cmd`.
- Confirm the WPF window opens without a console dependency.
- Confirm the app icon appears correctly.

## Runtime Checks

- Run `windows/scripts/allow-firewall.ps1` from an Administrator PowerShell session.
- Start the Windows app and confirm it advertises/discovers peers on the local LAN.
- Pair with a Mac dev build and compare the 6-digit dev PIN on both sides.
- Verify Mac -> Windows cursor handoff across the configured edge.
- Verify Windows -> Mac cursor handoff across the configured edge.
- Verify text clipboard sync both directions with non-sensitive sample text.
- Verify PNG clipboard sync with a non-sensitive test image.
- Verify file bundle sync with a small dummy file.
- Trigger disconnect/link loss and confirm local control returns.
- Export diagnostics and confirm they do not contain keystrokes, clipboard payloads, file bytes, PINs, or private keys.

## Result

Record:

- Windows version and architecture.
- BarelyReal release tag.
- Commit SHA.
- Passed checks.
- Failed checks with logs.
- Whether the release notes should be updated.
