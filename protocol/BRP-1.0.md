# BarelyReal Protocol (BRP) v1.0

Wire-format spec for KM, clipboard, and file sharing between BarelyReal peers.

All multi-byte integers are **little-endian**.

## Channels

| Channel    | Transport       | Purpose                                                            |
|------------|-----------------|--------------------------------------------------------------------|
| KM         | UDP, port 24801 | Mouse/keyboard events. Latency-sensitive. Lossy OK.                |
| Control    | TCP+TLS 24800   | Pairing, layout sync, role switch, ownership transfer, hotkeys.    |
| Clipboard  | TCP+TLS 24800   | Clipboard contents (text/html/image/RTF). Sub-stream of control.   |
| Files      | TCP+TLS 24800   | File transfer chunks for drag&drop. Sub-stream of control.         |

The target **control connection** is a single TLS 1.3 stream multiplexed by message type. KM is a separate UDP socket with its own AEAD layer (see § Security).

Implementation note: the current dev build already uses this control framing on TCP `24800`,
but it is still clear TCP while TLS/PIN pairing is being finished. The dev channel is used for
`Hello`, `ScreenAnnounce`, `LayoutSync`, and `KeepAlive`.

## Discovery

mDNS service: `_barelyreal._tcp.local.`

TXT records:
- `name=<device-name>` — UTF-8, max 63 bytes.
- `os=mac|win`
- `ver=<semver>` — protocol version.
- `peer_id=mac|windows` — current single-pair peer role identifier.
- `pk=<base64-sha256>` — fingerprint of device public key (32 bytes → base64 raw).

## Pairing (TOFU + 6-digit PIN)

1. Initiator opens TLS 1.3 connection to discovered peer (self-signed cert).
2. Both sides compute a 6-digit short-authentication-string (SAS) from the TLS 1.3 exporter:

   ```
   sas = HKDF-Expand-Label(exporter_master_secret, "barelyreal sas", "", 4) mod 1_000_000
   ```

   Decimal-padded to 6 digits.
3. Initiator UI displays `sas`; responder UI prompts user to type it.
4. On match, both sides pin the peer's certificate's SubjectPublicKeyInfo SHA-256 to local trust store.
5. On mismatch or 5 wrong attempts → connection dropped, 60 s lockout per peer key.

After pairing, future TLS connections require the pinned SPKI hash.

## Control Frames

```
struct ControlFrame {
    u32 length;          // length of [type|body], NOT including these 4 bytes
    u8  type;            // see ControlType
    u8  body[length-1];  // JSON UTF-8 unless noted
}
```

### `ControlType`

| Code  | Name                | Body                                                                 |
|-------|---------------------|----------------------------------------------------------------------|
| 0x01  | Hello               | `{"name","os","ver","screens":[…]}`                                  |
| 0x02  | LayoutSync          | `{"layout":[{"peer_id","screen_id","x","y","w","h"}, …]}`            |
| 0x03  | RoleSwitch          | `{"new_server":"<peer-id>"}`                                         |
| 0x04  | OwnershipTransfer   | `{"target_screen","entry_x","entry_y","drag":bool}`                  |
| 0x05  | ScreenAnnounce      | `{"peer_id","screens":[{"id","x","y","w","h","scale","primary"}, …]}` |
| 0x06  | WakeOnLanRequest    | `{"mac":"AA:BB:CC:DD:EE:FF","broadcast":"192.168.1.255"}`            |
| 0x07  | Hotkey              | `{"id":"force_switch"}`                                              |
| 0x10  | ClipboardOffer      | `{"id":u64,"formats":["text/plain","image/png", …]}`                 |
| 0x11  | ClipboardRequest    | `{"id":u64,"format":"image/png"}`                                    |
| 0x12  | ClipboardData       | binary: `[id:u64][fmt_len:u16][fmt:utf8][size:u32][bytes]`           |
| 0x20  | FileOffer           | `{"id":u64,"name","size":u64,"sha256":"<hex>"}`                      |
| 0x21  | FileChunk           | binary: `[id:u64][offset:u64][len:u32][data][chunk_sha256:32]`       |
| 0x22  | FileAck             | `{"id":u64,"offset":u64}`                                            |
| 0x23  | FileEnd             | `{"id":u64,"ok":bool,"reason"?}`                                     |
| 0xF0  | KeepAlive           | `{}` — sent every 5 s on control channel                             |
| 0xF1  | Bye                 | `{"reason"?}`                                                        |

JSON bodies are UTF-8, no BOM. Binary bodies (0x12, 0x21) replace the JSON body for those types only.

### Clipboard sub-protocol (current dev/scaffold layer)

Until the multiplexed control channel exists, clipboard sync runs on its own TCP port (default 24802) with a much simpler framing:

```
struct ClipboardFrame {
    u32 length;          // = 1 + payload size, little-endian
    u8  kind;            // 1 = text/plain UTF-8
                         // 2 = image/png
                         // 3 = file bundle (see below)
    u8  payload[length-1];
}
```

`kind = 3` (FileBundle) wire format:

```
u32 fileCount                  (≤ 64)
for each file:
    u16 nameLen                (≤ 1024 bytes UTF-8)
    utf8 name                  (sanitized: no path separators, no '.'/'..',
                                no NUL; '/', '\\' and ':' are replaced with '_')
    u64 size                   (≤ 200_000_000)
    bytes[size]
```

Total bundle size is also capped at 200 MB. Receivers write files into
`~/Downloads/BarelyReal/<timestamp>/` (macOS) or `%USERPROFILE%\Downloads\BarelyReal\<timestamp>\` (Windows)
and place those URLs onto the local clipboard so the user can paste them in Finder/Explorer.

Directories are not supported in MVP — sources skip them. A single bundle of files moves in one
TCP transaction.

## KM Frames (UDP)

```
struct KmFrame {
    u32 seq;             // monotonic per-sender, wraps
    u64 timestamp_us;    // sender clock, microseconds since UNIX epoch
    u8  type;            // see KmType
    u8  payload[…];      // type-dependent
}
```

KM frames are encrypted with ChaCha20-Poly1305 using a key derived from the TLS exporter (`HKDF "barelyreal km"`); nonce = `seq || zero-padded`. Receiver drops any frame whose `seq` is older than `max_seen − 1024` (replay protection) or fails AEAD.

Implementation note: the current dev build can still send raw `KmFrame` bytes
for smoke tests. When a KM shared secret is configured, each UDP datagram uses a
temporary authenticated envelope until TLS exporter key material exists:

```
struct DevKmEnvelope {
    u8 magic[4] = "BRKM";
    u8 version = 1;
    u8 algorithm = 1;    // HMAC-SHA256
    u16 flags = 0;
    u32 inner_len;
    u8 inner[inner_len]; // raw KmFrame bytes
    u8 tag[32];          // HMAC(header || inner)
}
```

The HMAC key is `SHA256("BarelyReal UDP KM v1\\0" || trim(shared_secret))`.
Receivers apply replay rejection only in authenticated mode, using separate
1024-frame windows for flow frames (`Heartbeat`, `ClockSync`) and input frames
(mouse/keyboard/modifiers). This split is required while the dev senders still
use separate sequence ranges for heartbeat and input. The envelope is a
dev-mode authentication guard only; it does not provide confidentiality and
must be replaced by the AEAD layer for release builds.

### `KmType`

| Code  | Name              | Payload                                                                  |
|-------|-------------------|--------------------------------------------------------------------------|
| 0x01  | MouseMoveRel      | `i32 dx; i32 dy;`                                                        |
| 0x02  | MouseMoveAbs      | `i32 x; i32 y;` absolute virtual desktop coordinates                     |
| 0x03  | MouseButton       | `u8 button; u8 down;` (button: 0=left,1=right,2=mid,3=x1,4=x2)           |
| 0x04  | MouseScroll       | `i32 dx; i32 dy;`                                                        |
| 0x05  | KeyDown           | `u16 keycode; u64 flags;`                                                |
| 0x06  | KeyUp             | `u16 keycode; u64 flags;`                                                |
| 0x07  | ModifiersChanged  | `u64 flags;`                                                            |
| 0xFE  | Heartbeat         | empty                                                                    |
| 0xFF  | ClockSync         | `u64 sender_t_us;` (echoed for RTT/skew estimation)                      |

`keycode`/`flags` are currently native-to-sender values in the scaffold (`CGKeyCode`/`CGEventFlags` on macOS, scan code/hook flags on Windows). Before the first interoperable alpha, this should be promoted to canonical HID Usage IDs plus the modifier bitmask below.

### Modifier bitmask

```
0x0001 LeftShift   0x0002 RightShift
0x0004 LeftCtrl    0x0008 RightCtrl
0x0010 LeftAlt     0x0020 RightAlt   (= macOS Option)
0x0040 LeftGui     0x0080 RightGui   (= macOS Cmd / Windows key)
0x0100 CapsLock    0x0200 NumLock    0x0400 ScrollLock
```

### Keycodes

HID Usage IDs (USB HID Usage Tables, Page 0x07). Each side translates to/from native keycodes:
- macOS: `kVK_*` ↔ HID via `IOHIDKeyboardUsage` mapping table.
- Windows: VK ↔ HID via `MapVirtualKeyEx(MAPVK_VK_TO_VSC_EX)`.

## Heartbeat & timeouts

- KM-канал: `Heartbeat` каждые 50 ms while owning input. Receiver tolerates gap up to 1500 ms before declaring link down → drops ownership and (if enabled) locks screen.
- Control-канал: `KeepAlive` каждые 5 s. TCP RST or 30 s silence → reconnect with backoff 1s → 30s.

## Clock sync

At connect, peers exchange 16 `ClockSync` frames over UDP (200 ms apart). Each side records min RTT and computes offset = `(t_remote − t_local) − rtt/2`. Used for latency telemetry and ordering of late-arriving KM frames.

## Versioning

`Hello.ver` is `MAJOR.MINOR.PATCH`. Peers MUST drop the connection if MAJOR differs. MINOR additions are backward-compatible (unknown control types ignored, unknown KM types dropped).

## Reserved type codes

`0x80–0xEF` reserved for future control types. `0x08–0xFD` reserved for future KM types.
