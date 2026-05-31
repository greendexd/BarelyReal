# Demo Media Checklist

BarelyReal should use real demo media, not mockups, once both platform builds
are runtime verified.

## Required Clips

- macOS app window showing Home, Devices, Activity, and Settings.
- Windows WPF app window showing peer connection state.
- Mac -> Windows cursor handoff across a configured screen edge.
- Windows -> Mac cursor handoff across a configured screen edge.
- Text clipboard sync using non-sensitive sample text.
- File transfer using a small dummy file.
- Diagnostics export showing sanitized metadata only.

## Capture Rules

- Use a clean desktop with no personal notifications.
- Use fake device names and non-sensitive test payloads.
- Do not show passwords, tokens, private chats, real clipboard history, personal files, or IP addresses outside a private LAN range.
- Prefer a short `.mp4` attached to the release and a compressed `.gif` or still image in README.

## README Placement

After real media exists, replace `docs/assets/barelyreal-system-preview.svg`
with:

- `docs/assets/barelyreal-demo.gif` for the README.
- `docs/assets/barelyreal-macos.png` for the macOS UI.
- `docs/assets/barelyreal-windows.png` for the Windows UI.
