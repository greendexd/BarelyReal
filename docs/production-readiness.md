# BarelyReal Production Readiness Roadmap

This roadmap moves BarelyReal from the current dev bridge to a shippable
macOS + Windows shared-desktop utility. It is aligned with:

- [README.md](../README.md), which describes the current raw UDP KM path,
  clear TCP dev control channel, and platform build commands.
- [docs/architecture.md](architecture.md), which defines the 1:1 P2P MVP,
  process layout, layout engine, feature scope, and latency targets.
- [docs/security.md](security.md), which defines the release security model:
  TLS 1.3, 6-digit PIN pairing, peer pinning, AEAD for UDP KM, no telemetry,
  and no plaintext fallback.
- [protocol/BRP-1.0.md](../protocol/BRP-1.0.md), which defines the BRP
  channel layout and frame formats.

## Shippable Definition

BarelyReal is shippable when a normal Mac user and a normal Windows user can
install signed builds, pair two devices on a hostile local network without
trusting the network, move keyboard/mouse control both ways across configured
screen edges, sync clipboard and files within documented limits, recover local
input on disconnect/crash/sleep, and uninstall or disable the app without
leaving hidden background behavior.

Release builds must not expose the current dev-mode plaintext channels. Raw
UDP KM frames, clear TCP control on `24800`, and standalone clear TCP clipboard
sync on `24802` are acceptable only behind explicit debug/developer switches
that cannot be enabled accidentally in public builds.

## Current Baseline

The repository is in early development. Current strengths:

- Shared BRP frame codecs and byte fixtures exist on macOS and Windows.
- macOS has a launchable Swift/AppKit/SwiftUI app with KM edge mode,
  multi-monitor layout editor, permission checks, clipboard test actions, Wake
  on LAN, and local clipboard history.
- Windows has a .NET 8 WPF dev app, KM receive/send paths, layout canvas,
  clipboard sync, smoke tools, firewall helper, and verification script.
- Dev control/layout sync works over clear TCP `24800` for `Hello`,
  `ScreenAnnounce`, `LayoutSync`, and `KeepAlive`.
- Dev mDNS/Bonjour publish/browse works on `_barelyreal._tcp.local.` and fills
  the existing peer IP fields while preserving manual fallback.
- Dev KM works over UDP `24801` with trusted peer IP source filtering and
  optional `BRKM` HMAC-SHA256 datagram authentication via a session-only shared
  secret. Authenticated dev mode also drops duplicate and old KM frames with a
  1024-frame replay window.
- Dev clipboard sync uses TCP `24802` for text, PNG images, and file bundles.
- Pairing, identity, TLS, file transfer, and release packaging have
  scaffolding or docs, but not enough enforced behavior for public release.

Non-negotiable gaps before release:

- TLS 1.3 control channel must replace clear TCP for release builds.
- UDP KM must still be encrypted and replay-protected with exporter-derived
  AEAD; source filtering and the temporary HMAC shared secret are dev-mode
  guards, not final pairing.
- PIN pairing, peer pinning, lockout, identity reset, and MITM handling must be
  connected to both UIs and persisted correctly.
- macOS Accessibility and Input Monitoring flows must be reliable for the
  installed app bundle, not just terminal tools.
- Windows injection into normal and elevated windows must have clear privilege
  behavior and user-visible state.
- Clipboard and file transfer must follow the logging and size-limit rules in
  the security and protocol docs.
- Mac and Windows runtime behavior must be verified on real Mac and Windows
  machines; cross-compiling on macOS is not sufficient for Windows runtime.

## Phase 0 - Freeze the Dev Baseline

Goal: keep the current dev bridge reproducible while security and product work
land around it.

Work:

- Preserve the current Mac-to-Windows and Windows-to-Mac dev flows.
- Keep dev-only code paths named and surfaced as dev-only in UI/logs.
- Add or maintain sanitized diagnostics on both platforms. Diagnostics may
  include connection state, frame counts, latency, ports, permissions, and
  errors, but never keystrokes, clipboard payloads, or file bytes.
- Make build and smoke commands the minimum gate for every change touching
  protocol, KM, clipboard, layout, networking, packaging, or permissions.
- Keep generated build artifacts, logs, app bundles, zips, and local secrets out
  of commits.

Release gate:

- macOS: `cd mac && swift build && swift run BarelyRealTests && swift run BarelyRealKmSmoke udp-loopback`.
- macOS installed-app check: `./mac/scripts/install_app.sh`, then
  `codesign --verify --deep --strict /Applications/BarelyReal.app`.
- Windows: `powershell -ExecutionPolicy Bypass -File windows/scripts/verify.ps1`
  on a real Windows machine.
- Optional Mac-side Windows compile check:
  `dotnet build windows/BarelyReal.sln --nologo -warnaserror`; this does not
  replace Windows runtime verification.

Acceptance criteria:

- Existing dev bridge still works in both directions after changes.
- Layout sync still shows all local and peer displays.
- Link-loss recovery returns control locally within the documented heartbeat
  timeout.
- Diagnostics are useful enough for support triage and contain no sensitive
  payload content.
- README remains honest about what is dev mode versus release behavior.

## Phase 1 - Secure Pairing and Transport

Goal: make BRP secure by default and remove plaintext release behavior.

Work:

- Implement `TlsSession` on macOS with `Network.framework` TLS 1.3 and on
  Windows with `SslStream`/Schannel.
- Bind the TLS certificate to each platform's durable `DeviceIdentity`.
- Generate and store local identity in Keychain on macOS and DPAPI-protected
  user storage on Windows.
- Implement 6-digit SAS/PIN pairing from the TLS exporter.
- Persist pinned peer SPKI hashes.
- Enforce exact peer pin matches on future connections.
- Persist wrong-attempt counters and lockouts across app restarts.
- Provide unpair/reset identity flows with clear consequences.
- Move control, layout, clipboard, and file sub-streams onto the TLS control
  connection on `24800`.
- Derive UDP KM encryption keys from TLS exporter material.
- Wrap KM frames with ChaCha20-Poly1305 or the approved platform equivalent,
  including sequence numbers, nonce construction, and replay rejection.
- Fail closed when TLS, pinning, exporter derivation, or AEAD verification
  fails.
- Implement mDNS publish/browse for `_barelyreal._tcp.local.` with device name,
  OS, protocol version, and public-key fingerprint TXT records.
- Keep protocol version negotiation strict: major mismatch drops connection,
  minor additions ignore unknown types safely.

Release gate:

- A release build cannot send KM, clipboard, file, or control data over
  plaintext.
- A peer-pin mismatch produces a hard connection failure and visible user
  notification.
- Five wrong PIN attempts cause a 60-second lockout, and the lockout survives
  restart.
- After 25 wrong attempts, pairing requires manual re-enable in settings.
- Pairing reset removes only BarelyReal trust state and does not touch unrelated
  Keychain/DPAPI data.

Acceptance criteria:

- Fresh Mac/Windows pair succeeds via mDNS discovery and manual IP fallback.
- Existing pair reconnects without re-pairing and rejects changed peer keys.
- MITM simulation on the same LAN cannot complete pairing silently.
- Captured network traffic contains no plaintext keystrokes, clipboard payloads,
  file bytes, layout secrets beyond mDNS TXT data, or PIN values.
- Raw dev transport still exists only as an explicit developer mode with
  unmistakable UI/log labeling and disabled in public packaging.

## Phase 2 - Product App Shells and Permissions

Goal: turn the two dev apps into everyday desktop utilities.

macOS work:

- Keep the app bundle identity stable across builds.
- Ensure Accessibility and Input Monitoring flows call the runtime APIs needed
  for the installed bundle to appear in System Settings.
- Verify the app from `/Applications/BarelyReal.app`, not only `swift run`.
- Keep the emergency return-to-Mac shortcut available even when remote input is
  active.
- Auto-return local input on lock, sleep, app quit, crash, link loss, or peer
  disconnect.
- Make status item, main window, devices, clipboard, activity, and settings
  usable without terminal tools.
- Make permissions state visible without exposing sensitive data.

Windows work:

- Decide whether WPF ships for v1 or whether WinUI/tray migration is required.
  This decision should be based on reliability, tray/background behavior,
  signing/installer support, and expected UX, not preference alone.
- Provide a real tray/background mode with explicit quit/disable controls.
- Keep firewall setup clear and limited to the required local ports/profiles.
- Run as normal user by default.
- Make elevated mode opt-in, visibly indicated, and used only when injecting
  into elevated windows is required.
- Persist settings and peer trust under user scope.
- Keep WPF/WinUI app startup, sleep/wake, reconnect, and diagnostics covered by
  Windows-side runtime tests.

Shared app work:

- One pairing flow for discovered peers and manual IP peers.
- One devices/layout editor that handles multiple monitors per peer.
- One activity view that shows connection state, errors, permissions, and
  sanitized diagnostics.
- One settings model for transport, layout, modifier remaps, clipboard/file
  sync, lock-on-disconnect, Wake on LAN, and developer mode.

Release gate:

- A non-developer can install, launch, pair, connect, disconnect, unpair, and
  quit on both platforms without reading terminal instructions.
- The app always has a visible state when it is capturing, injecting, elevated,
  disconnected, locked out, or running in developer mode.
- A failed permission, firewall, or elevation setup produces a specific next
  action rather than a silent failure.

Acceptance criteria:

- macOS app appears in the correct Privacy & Security lists for the installed
  bundle ID.
- Windows app receives and injects input in normal user sessions.
- Elevated Windows mode is opt-in and visibly active when enabled.
- Quitting either app restores local input and releases cursor constraints.
- Re-launching after reboot preserves trusted peers and user settings.

## Phase 3 - Complete Sharing Features

Goal: finish the user-visible MVP features from the architecture doc.

KM and layout:

- Bidirectional Mac-to-Windows and Windows-to-Mac ownership transfer.
- Edge transition using the shared virtual layout for any bordering edge.
- Force-switch hotkey on both platforms.
- Multi-monitor enumeration and layout sync for mixed scale factors, primary
  display changes, negative coordinates, and display hotplug.
- Canonical HID usage IDs and modifier bitmask across both platforms.
- Cmd/Ctrl and Option/Alt remap with override table.
- Scroll speed and high-resolution wheel behavior.
- Drag preservation when crossing edges.
- Remote cursor recovery if the peer drops mid-drag or mid-key chord.

Clipboard:

- Text/plain, text/html, image/png, and RTF over the TLS control channel.
- File bundle compatibility with the current dev framing until full file
  transfer is connected.
- Loop prevention so remote clipboard application does not echo forever.
- Size caps and refusal UI for oversized payloads.
- Local-only clipboard history with user-visible clear/disable controls.
- No clipboard payloads in logs, diagnostics, crash reports, or test output.

Files:

- Drag-and-drop file transfer over BRP `FileOffer`, `FileChunk`, `FileAck`, and
  `FileEnd`.
- Overlay drop-zone fallback when native drag across screens is not reliable.
- SHA-256 verification and refusal on mismatch.
- Safe destination handling under `~/Downloads/BarelyReal/<timestamp>/` on
  macOS and `%USERPROFILE%\Downloads\BarelyReal\<timestamp>\` on Windows.
- Documented limits for file count, single-file size, total bundle size, and
  directory handling.

USB-C/direct link:

- Define the supported v1 path: direct network link over USB-C, not custom USB
  device firmware.
- Document how discovery and manual IP work on the direct link.
- Measure latency separately from Wi-Fi.

Release gate:

- Every feature advertised in README and onboarding has a passing manual or
  automated test on both platforms.
- Unsupported cases are blocked with clear UI and documentation, not partial
  behavior.

Acceptance criteria:

- Users can complete a normal work session with a single keyboard/mouse across
  both machines without terminal tools.
- Clipboard formats round-trip both directions without corruption.
- File transfer either completes with verified bytes or fails with no partial
  clipboard state presented as success.
- Display layout remains accurate after reconnect, display hotplug, and scale
  changes.

## Phase 4 - Reliability, Performance, and Recovery

Goal: make the app boring under real desk conditions.

Work:

- Measure KM end-to-end latency on Wi-Fi and USB-C/direct link.
- Keep target budgets from the architecture doc: sub-10 ms on Wi-Fi and sub-3
  ms on USB-C where the environment supports it.
- Add reconnect with bounded backoff for control and KM paths.
- Treat TCP RST, UDP heartbeat timeout, app crash, sleep/wake, network profile
  change, and display topology change as first-class recovery cases.
- Keep lock-on-disconnect opt-in and make the default non-destructive.
- Track frame counts, dropped frames, replay drops, RTT, reconnect counts, and
  last error without logging input content.
- Add soak tests for idle, active typing, active mouse movement, clipboard
  churn, file transfer, and sleep/wake cycles.
- Verify high CPU load, low battery, flaky Wi-Fi, VPN enabled, and firewall
  profile changes.

Release gate:

- No known path can leave the user stuck on the peer machine without a local
  recovery shortcut or timeout.
- A 4-hour active soak has no input lockup, unbounded memory growth, unbounded
  log growth, clipboard echo loop, or runaway reconnect loop.
- Latency and packet loss numbers are recorded for release notes.

Acceptance criteria:

- Losing either process restores local control on the surviving process.
- Losing the network restores local input and reconnects when the peer returns.
- Sleep/wake on either machine does not require deleting trust state.
- Logs rotate at the documented limit and exclude sensitive payloads.

## Phase 5 - Packaging, Signing, and Installation

Goal: make install/update/uninstall trustworthy on both platforms.

macOS work:

- Produce a signed and notarized app bundle.
- Choose distribution artifact: zip for early beta, DMG or PKG if install UX
  requires it.
- Preserve bundle ID and signing identity so TCC permissions do not reset
  unnecessarily between updates.
- Verify Gatekeeper launch from a downloaded artifact.
- Verify SHA-256 generation and release artifact integrity.
- Provide uninstall instructions for app bundle, settings, logs, and trust
  state.

Windows work:

- Produce a signed installer or app package.
- Decide MSIX versus classic installer based on tray/background behavior,
  firewall rule setup, elevation mode, uninstall behavior, and update path.
- Keep firewall rules limited, named, and removable on uninstall.
- Verify SmartScreen/code-signing behavior as far as available before public
  beta.
- Provide uninstall instructions for app files, settings, logs, firewall rules,
  and trust state.

Shared work:

- Keep dev builds clearly branded as dev builds.
- Keep release builds free of developer-mode defaults.
- Include version, protocol version, build hash, signing status, and channel in
  diagnostics.
- Decide update strategy before beta: manual download is acceptable for early
  beta if documented; silent auto-update is not required for v1.

Release gate:

- Fresh install, update install, downgrade block, and uninstall are tested on
  both platforms.
- Public artifacts are signed, reproducible enough for support, and have
  recorded SHA-256 hashes.
- A user can remove BarelyReal and verify that it no longer runs in the
  background or listens on its ports.

Acceptance criteria:

- macOS artifact launches after download without terminal commands.
- Windows artifact installs and uninstalls through normal Windows UI.
- No autostart is created unless the user explicitly enables it.
- Disabling or quitting the app stops capture, injection, listening sockets, and
  clipboard/file sync.

## Phase 6 - Beta, RC, and Stable Release

Goal: release only after the product survives real user desks.

Alpha:

- Audience: developer machines only.
- Allowed: explicit dev mode, manual IP, known rough UI, terminal diagnostics.
- Required: no source regressions, no stuck-input bugs, no sensitive logging.

Private beta:

- Audience: trusted external users.
- Required: secure transport on by default, signed builds, pairing UI, normal
  install/uninstall, sanitized diagnostics, documented unsupported cases.
- Exit: at least 10 multi-hour sessions across different Mac/Windows hardware
  without stuck input or trust reset.

Release candidate:

- Audience: release validation only.
- Required: no plaintext release channels, complete audit checklist, packaging
  signed/notarized, user docs updated, test matrix complete.
- Exit: no open P0/P1 bugs, no known security bypass, no forced terminal step
  for normal workflows.

Stable v1.0:

- Audience: public users who match documented requirements.
- Required: release notes, known issues, uninstall docs, support diagnostics,
  artifact hashes, and a rollback plan.

## Release Gates

| Gate | Area | Must pass |
|------|------|-----------|
| G0 | Scope | v1 remains 1:1 Mac + Windows, no third-party servers, no telemetry, no multi-peer claims. |
| G1 | Source hygiene | No committed build outputs, logs, app bundles, zips, local secrets, or generated artifacts outside intended release output. |
| G2 | Automated tests | Mac Swift tests, Windows .NET tests, shared protocol fixture tests, UDP loopback smoke, and build warnings-as-errors pass. |
| G3 | Security | TLS 1.3, PIN pairing, peer pinning, persisted lockout, AEAD UDP KM, no plaintext release fallback, no sensitive logs. |
| G4 | Permissions | macOS Accessibility/Input Monitoring and Windows firewall/elevation states are user-visible, recoverable, and verified on installed apps. |
| G5 | Interop | Mac-to-Windows and Windows-to-Mac KM, clipboard, layout sync, reconnect, and file transfer work across real machines. |
| G6 | Recovery | Crash, quit, sleep, lock, network loss, peer loss, display hotplug, and failed pairing all restore safe local state. |
| G7 | Performance | Latency, packet loss, CPU, memory, and log growth stay within documented thresholds during active and idle soaks. |
| G8 | Packaging | Signed/notarized Mac artifact and signed Windows installer/package install, update, uninstall, and leave no hidden autostart. |
| G9 | Documentation | README, security, architecture, install/uninstall, troubleshooting, and known issues match actual release behavior. |

No gate can be waived for stable release if it affects plaintext transport,
input recovery, permission correctness, uninstall behavior, or sensitive data
logging.

## Key Risks

- Security drift: the dev TCP/UDP path is useful now but dangerous if it leaks
  into public builds. Mitigation: compile-time or packaging-level release
  checks that fail when plaintext developer mode is enabled by default.
- macOS TCC fragility: permission prompts depend on bundle ID, signing, install
  path, and runtime API calls. Mitigation: test the installed app from
  `/Applications`, reset TCC during validation, and verify the app appears in
  Privacy & Security lists.
- Windows privilege boundaries: low-level hooks and injection behave
  differently across normal windows, elevated windows, UAC surfaces, games, and
  secure desktops. Mitigation: normal-user default, opt-in elevation, visible
  state, and clear unsupported cases.
- Stuck remote input: a crash or network loss during remote ownership is the
  highest user-trust failure. Mitigation: local emergency hotkey, heartbeat
  timeout, auto-return on sleep/lock, and recovery tests before every beta.
- Multi-monitor coordinate errors: mixed DPI, negative coordinates, display
  hotplug, and non-rectangular layouts can cause wrong edge transitions.
  Mitigation: shared layout fixtures plus real hardware tests.
- Clipboard/file data exposure: payloads can include passwords, private images,
  and documents. Mitigation: TLS, no payload logging, size caps, local-only
  history controls, and explicit diagnostics review.
- Discovery/firewall instability: mDNS and inbound sockets vary by network
  profile, VPN, and firewall. Mitigation: manual IP fallback, precise firewall
  rules, and runtime diagnostics.
- USB-C expectations: "USB-C support" can mean direct network link, Thunderbolt
  bridge, or custom device behavior. Mitigation: define v1 as direct network
  link over USB-C and document setup/limits.
- Packaging identity changes: signing identity or bundle/package ID changes can
  reset permissions and trust. Mitigation: lock identifiers before beta.
- Cross-platform drift: Mac-side compile checks do not prove Windows runtime.
  Mitigation: Windows verification remains a release gate on real Windows.

## Test Matrix

### Automated Build and Unit Tests

| ID | Test | Platform | Command or method | Pass criteria |
|----|------|----------|-------------------|---------------|
| A1 | Mac build | macOS | `cd mac && swift build` | Build succeeds without new warnings that indicate release risk. |
| A2 | Mac tests | macOS | `cd mac && swift run BarelyRealTests` | Protocol, KM, layout, clipboard/file fixture tests pass. |
| A3 | Mac UDP loopback | macOS | `cd mac && swift run BarelyRealKmSmoke udp-loopback` | Loopback sends and receives valid KM frames. |
| A4 | Mac install bundle | macOS | `./mac/scripts/install_app.sh` | App installs to `/Applications` or documented fallback path. |
| A5 | Mac code signature | macOS | `codesign --verify --deep --strict /Applications/BarelyReal.app` | Installed app signature verifies. |
| A6 | Mac package | macOS | `./mac/scripts/package_app.sh` | Zip and SHA-256 are produced; hash verifies from `mac/dist`. |
| A7 | Windows verify | Windows | `powershell -ExecutionPolicy Bypass -File windows/scripts/verify.ps1` | Restore, build, tests, and UDP smoke pass. |
| A8 | Windows compile smoke on Mac | macOS | `dotnet build windows/BarelyReal.sln --nologo -warnaserror` | Compile succeeds; result is not treated as Windows runtime proof. |

### Security and Pairing Tests

| ID | Test | Platform | Method | Pass criteria |
|----|------|----------|--------|---------------|
| S1 | Fresh pairing | Mac + Windows | Discover via mDNS, pair with 6-digit PIN. | Both sides pin peer and reconnect without re-pairing. |
| S2 | Manual IP pairing | Mac + Windows | Disable discovery and connect by IP. | Pairing and reconnect behavior match discovery path. |
| S3 | Wrong PIN lockout | Mac + Windows | Enter wrong PIN 5 times, restart apps. | Lockout remains active and shows retry time. |
| S4 | 25-attempt protection | Mac + Windows | Continue failed attempts past policy threshold. | Pairing requires manual re-enable in settings. |
| S5 | Peer key mismatch | Mac + Windows | Reset one peer identity after pairing. | Connection hard-fails with MITM-style warning. |
| S6 | Network capture | Mac + Windows | Capture LAN traffic during KM, clipboard, and file transfer. | No plaintext keystrokes, clipboard payloads, file bytes, or PIN values. |
| S7 | UDP replay | Mac + Windows | Replay old encrypted KM packets. | Receiver drops old or invalid frames. |
| S8 | Release plaintext audit | CI/local release build | Search binary/config/build flags and run traffic check. | Public build cannot enable raw dev transport by default. |
| S9 | Log hygiene | Mac + Windows | Generate logs/diagnostics during sensitive input and clipboard use. | Logs contain state/error/metrics only, no payloads. |

### Runtime Interop Tests

| ID | Test | Platform | Method | Pass criteria |
|----|------|----------|--------|---------------|
| R1 | Mac to Windows KM | Mac host, Windows guest | Move across configured edge, type, click, scroll. | Windows receives correct input; Mac local cursor recovers on return. |
| R2 | Windows to Mac KM | Windows host, Mac guest | Move across configured edge, type, click, scroll. | Mac receives correct input; Windows local cursor recovers on return. |
| R3 | Force-switch hotkey | Mac + Windows | Trigger default hotkey while local and remote. | Ownership switches or returns predictably with visible state. |
| R4 | Modifier remap | Mac + Windows | Test Cmd/Ctrl, Option/Alt, Shift, Caps Lock, shortcuts. | Shortcuts behave according to configured remap table. |
| R5 | Drag across edge | Mac + Windows | Begin drag locally and cross to peer. | Drag is preserved or clear fallback appears. |
| R6 | Multi-monitor layout | Mac + Windows | Test left/right/top/bottom/corner layouts, mixed DPI, negative coordinates. | Edge transfer maps to correct peer display and returns correctly. |
| R7 | Display hotplug | Mac + Windows | Add/remove external monitor while connected. | Layout sync updates without stuck ownership. |
| R8 | Sleep/wake | Mac + Windows | Sleep and wake each side while connected and while remote. | Local input returns and reconnect succeeds without trust reset. |
| R9 | Link loss | Mac + Windows | Disable Wi-Fi/unplug network during remote control. | Local input returns within heartbeat timeout. |
| R10 | Process crash | Mac + Windows | Kill peer app during active remote control. | Surviving side restores local state and logs sanitized error. |

### Clipboard and File Tests

| ID | Test | Platform | Method | Pass criteria |
|----|------|----------|--------|---------------|
| C1 | Plain text | Mac to Windows, Windows to Mac | Copy/paste ASCII, Unicode, long text. | Content matches exactly and no echo loop occurs. |
| C2 | HTML | Mac to Windows, Windows to Mac | Copy rich text from browser/editor. | HTML and fallback text paste correctly where supported. |
| C3 | PNG image | Mac to Windows, Windows to Mac | Copy screenshot/image. | Image pastes with expected dimensions and bytes. |
| C4 | RTF | Mac to Windows, Windows to Mac | Copy styled text. | RTF arrives where supported, fallback is sane where not. |
| C5 | File bundle clipboard | Mac to Windows, Windows to Mac | Copy files under documented caps. | Files land in the documented Downloads folder and clipboard references them. |
| C6 | Oversized payload | Mac + Windows | Try payloads above single-file/total limits. | Transfer is refused with clear UI and no partial success state. |
| C7 | Unsafe filenames | Mac + Windows | Transfer names with separators, NUL-equivalent cases, dot segments. | Names are sanitized or refused. |
| C8 | File transfer checksum | Mac + Windows | Corrupt a chunk in transit or test harness. | Receiver refuses final file and reports sanitized error. |
| C9 | History controls | Mac + Windows | Enable, disable, clear history. | Local history follows user choice and never syncs as history metadata. |

### Packaging and Lifecycle Tests

| ID | Test | Platform | Method | Pass criteria |
|----|------|----------|--------|---------------|
| P1 | Fresh install | macOS | Install public artifact on clean user account. | App launches, requests permissions correctly, no terminal step required. |
| P2 | Fresh install | Windows | Install public artifact on clean user account. | App launches, firewall/elevation guidance is clear, no terminal step required. |
| P3 | Update install | Mac + Windows | Install newer build over previous trusted pair. | Settings and trust survive unless migration says otherwise. |
| P4 | Identifier stability | Mac + Windows | Compare bundle/package IDs and signing identity across builds. | Stable identifiers before beta and stable thereafter. |
| P5 | Quit/disable | Mac + Windows | Quit app and disable sharing. | Capture, injection, sockets, clipboard, and file sync stop. |
| P6 | Autostart | Mac + Windows | Enable and disable launch at login. | No autostart exists unless user enabled it; disabling removes it. |
| P7 | Uninstall | Mac + Windows | Remove app through documented path. | App no longer runs, listens, injects, captures, or autostarts. |
| P8 | Trust reset | Mac + Windows | Reset peers/identity from settings. | Only BarelyReal trust state is removed. |

### Performance and Soak Tests

| ID | Test | Platform | Method | Pass criteria |
|----|------|----------|--------|---------------|
| L1 | Wi-Fi latency | Mac + Windows | Measure active KM over typical LAN. | Median and p95 meet release target or are documented before beta. |
| L2 | USB-C/direct-link latency | Mac + Windows | Measure active KM over direct network link. | Median and p95 meet release target or setup is not advertised. |
| L3 | Active 4-hour soak | Mac + Windows | Move/type intermittently, sync clipboard, transfer files. | No lockup, unbounded memory/log growth, or reconnect storm. |
| L4 | Idle overnight soak | Mac + Windows | Paired and idle. | Connection remains stable or reconnects cleanly; logs rotate. |
| L5 | High CPU/low power | Mac + Windows | Run under CPU load and laptop power changes. | Input remains usable and recovery works. |
| L6 | Flaky network | Mac + Windows | Packet loss, latency, network profile changes, VPN on/off. | Failures are visible, local input returns, reconnect is bounded. |

## First Release Backlog Order

1. Land TLS, pairing, persisted trust, mDNS, and AEAD before expanding the public
   feature set.
2. Keep Mac and Windows app-shell work in parallel, but do not ship a polished UI
   over insecure transport.
3. Finish KM recovery paths before beta users spend full sessions in remote
   input mode.
4. Complete clipboard/file support with logging review and size-limit tests.
5. Lock bundle/package identifiers and signing before external beta.
6. Run the full test matrix on real Mac and Windows hardware before RC.
7. Update README, architecture, security, install, uninstall, and
   troubleshooting docs only after behavior matches the builds.
