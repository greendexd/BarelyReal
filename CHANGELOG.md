# Changelog

All notable BarelyReal changes are tracked here.

## Unreleased

- Added a manual GitHub Actions CI workflow for macOS Swift and Windows .NET verification.
- Added public roadmap, demo capture checklist, Windows release test checklist, and outreach guidance.

## v0.1.0-alpha.1 - 2026-05-31

Initial public alpha release.

- Published the repository under the MIT License.
- Added public source, contributing guide, security policy, issue templates, and pull request template.
- Added downloadable macOS and Windows x64 release archives.
- Enabled GitHub secret scanning, push protection, Dependabot alerts, and Dependabot update checks.
- macOS artifact: `BarelyReal-mac.zip`, ad-hoc signed and verified with `codesign --verify --deep --strict` after unzip.
- Windows artifact: `BarelyReal-win-x64.zip`, self-contained `win-x64` WPF app folder published with .NET 8.
- Verification:
  - `swift run BarelyRealTests`: 49 passed.
  - `swift run BarelyRealKmSmoke udp-loopback`: passed.
  - `dotnet build windows/BarelyReal.sln --no-restore -warnaserror`: passed.

Known alpha limitations:

- Current dev transports are not a production security boundary.
- macOS build is not Developer ID signed or notarized.
- Windows build is unsigned and may trigger SmartScreen.
- Windows runtime smoke testing still needs to be completed on a real Windows machine.
