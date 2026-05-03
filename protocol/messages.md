# BRP message catalog

Quick lookup table of message codes. Authoritative spec: [BRP-1.0.md](BRP-1.0.md).

## Control (TCP+TLS)

| Code | Name              |
|------|-------------------|
| 0x01 | Hello             |
| 0x02 | LayoutSync        |
| 0x03 | RoleSwitch        |
| 0x04 | OwnershipTransfer |
| 0x05 | ScreenAnnounce    |
| 0x06 | WakeOnLanRequest  |
| 0x07 | Hotkey            |
| 0x10 | ClipboardOffer    |
| 0x11 | ClipboardRequest  |
| 0x12 | ClipboardData     |
| 0x20 | FileOffer         |
| 0x21 | FileChunk         |
| 0x22 | FileAck           |
| 0x23 | FileEnd           |
| 0xF0 | KeepAlive         |
| 0xF1 | Bye               |

## KM (UDP, AEAD)

| Code | Name             |
|------|------------------|
| 0x01 | MouseMoveRel     |
| 0x02 | MouseMoveAbs     |
| 0x03 | MouseButton      |
| 0x04 | MouseScroll      |
| 0x05 | KeyDown          |
| 0x06 | KeyUp            |
| 0x07 | ModifiersChanged |
| 0xFE | Heartbeat        |
| 0xFF | ClockSync        |
