# BarelyReal — Architecture

## Goals

- Share one physical keyboard + mouse across a macOS host and a Windows host.
- Share clipboard contents (text, HTML, image, RTF) bidirectionally.
- Drag & drop files between machines.
- Work on a local network (Wi-Fi / Ethernet) and over a direct USB-C link.
- Sub-10 ms input latency on Wi-Fi, sub-3 ms on USB-C.
- No third-party servers, no telemetry.

## Topology

MVP supports a 1:1 peer pairing. Either machine can be the active "server" (the one whose physical KM is shared) at any time; role is dynamic and can flip via tray menu or hotkey. P2P design for v1.0 — multi-client support is a v2 goal.

## Process layout per machine

Single user-space process running:
- **NetworkService** — TLS+TCP control connection, UDP KM socket, mDNS advertiser/browser.
- **KMHost** — captures local KM events when this machine "owns input", sends them to the peer.
- **KMGuest** — receives KM events from the peer, injects them locally.
- **ClipboardSync** — listens to OS clipboard changes, mirrors to the peer.
- **FileTransfer** — handles drag&drop file streams.
- **LayoutEngine** — stores every local/remote screen in one virtual coordinate plane and decides ownership transfer at any bordering edge.
- **UI** — tray icon, layout editor, settings, pairing flow.

Roles `KMHost` and `KMGuest` are not mutually exclusive — a machine can host KM (capturing) most of the time and switch to guest (receiving) when ownership flips.

## Module map

```
mac/                                              windows/
├── App/                                          ├── App/
│   ├── StatusItemController.swift                │   ├── TrayIconController.cs
│   ├── LayoutEditorView.swift                    │   ├── Views/LayoutEditorPage.xaml
│   ├── PairingView.swift                         │   ├── Views/PairingPage.xaml
│   └── SettingsView.swift                        │   └── Views/SettingsPage.xaml
└── Core/                                         └── Core/
    ├── Protocol/                                     ├── Protocol/
    │   ├── KmFrame.swift                             │   ├── KmFrame.cs
    │   ├── ControlFrame.swift                        │   ├── ControlFrame.cs
    │   └── Codec.swift                               │   └── Codec.cs
    ├── Network/                                      ├── Network/
    │   ├── TlsSession.swift                          │   ├── TlsSession.cs
    │   ├── MdnsAdvertiser.swift                      │   ├── MdnsAdvertiser.cs
    │   ├── UdpKmStream.swift                         │   ├── UdpKmStream.cs
    │   └── PairingService.swift                      │   └── PairingService.cs
    ├── KM/                                           ├── Km/
    │   ├── EventTap.swift                            │   ├── LowLevelHooks.cs
    │   ├── EventInjector.swift                       │   ├── InputInjector.cs
    │   └── HotkeyManager.swift                       │   └── HotkeyManager.cs
    ├── Clipboard/                                    ├── Clipboard/
    │   ├── PasteboardSync.swift                      │   ├── ClipboardSync.cs
    │   └── ClipboardHistory.swift                    │   └── ClipboardHistory.cs
    ├── Layout/                                       ├── Layout/
    │   ├── LayoutEngine.swift                        │   ├── LayoutEngine.cs
    │   └── ScreenSnapshot.swift                      │   └── ScreenSnapshot.cs
    └── Files/                                        └── Files/
        └── FileTransfer.swift                            └── FileTransfer.cs
```

## Edge-transition flow

1. Both peers announce all OS-enumerated displays through the control channel (`ScreenAnnounce`) and keep a synced `LayoutSync` document.
2. Active host owns KM. Local cursor is visible; remote mode is inactive.
3. User moves mouse toward any physical edge. The host projects the next cursor point into the shared virtual layout.
4. If that projected point is inside a peer screen, the host:
   - sends a `MouseMoveAbs` UDP frame to the corresponding native point on the peer screen;
   - enters remote mode and hides/pins its local cursor (`CGAssociateMouseAndMouseCursorPosition(false)` on macOS / `ClipCursor` to a 1×1 region on Windows);
   - streams subsequent `MouseMoveRel`, `MouseButton`, `KeyDown`, `KeyUp`, etc. frames.
5. Reverse uses the same virtual layout: if the tracked remote virtual cursor crosses back into a local screen, the host restores the local cursor at that mapped point and exits remote mode.

Force-switch hotkey (default `Ctrl+Alt+S`) bypasses edge logic.

## Failure modes

| Event                              | Behavior                                                                |
|------------------------------------|-------------------------------------------------------------------------|
| Wi-Fi drops                        | KM heartbeat times out (1.5 s) → both sides revert to local input. Optional lock-on-disconnect kicks in. |
| Process crash on guest             | Host detects TCP RST → reverts to local input.                          |
| Peer not yet paired                | Discovery still works; UI shows "Pair to connect" CTA.                  |
| Clock drift                        | `ClockSync` exchanges keep skew estimate fresh; only used for telemetry. |
| Keymap mismatch                    | Modifier remap table applied at injector; HID Usage IDs are canonical.   |

## MVP scope

Per-feature acceptance criteria:

- ✅ Mouse + keyboard work across machines via Wi-Fi and via USB-C.
- ✅ Edge-transition + global hotkey switch.
- ✅ Visual layout configurator with multi-monitor support per peer.
- ✅ Clipboard sync: text/plain, text/html, image/png, application/rtf.
- ✅ Clipboard history (last 50 entries, local-only by default).
- ✅ Drag&drop files (with overlay drop-zone fallback).
- ✅ Cmd↔Ctrl / Option↔Alt remap with override table.
- ✅ Wake-on-LAN button to wake a sleeping peer.
- ✅ TLS 1.3 + 6-digit PIN pairing with public-key pinning.
- ✅ mDNS discovery.

Out of MVP (v2+): multi-peer (1:N), iOS/iPadOS clients, screen mirroring, audio routing.

## Build & dependencies

### macOS
- Swift 5.9 / Swift 6.0
- Targets macOS 14+
- Frameworks: Network, AppKit, SwiftUI, CoreGraphics, Carbon (hotkeys), Security (Keychain), UniformTypeIdentifiers.
- No third-party Swift packages for the core; SQLite via `GRDB` or built-in `sqlite3`.

### Windows
- .NET 8
- WinUI 3 (Windows App SDK 1.5+)
- NuGet:
  - `Makaretu.Dns.Multicast` — mDNS.
  - `H.NotifyIcon.WinUI` — tray icon.
  - `Microsoft.Data.Sqlite` — clipboard history.
- Win32 P/Invoke: `user32.dll`, `kernel32.dll`, `shell32.dll`, `ole32.dll`.
