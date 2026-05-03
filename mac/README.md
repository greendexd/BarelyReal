# BarelyReal macOS

SwiftPM targets:

```sh
swift build
swift run BarelyRealTests
swift run BarelyReal
swift run BarelyRealKmSmoke udp-loopback
```

The app UI now supports:

- Mac -> Windows KM sender mode.
- Windows -> Mac KM receiver mode.
- Text, PNG, and file clipboard sync.
- Wake-on-LAN packet sending.
- Optional lock-on-disconnect while receiving KM.

Manual KM smoke:

```sh
swift run BarelyRealKmSmoke udp-loopback
swift run BarelyRealKmSmoke capture 10
swift run BarelyRealKmSmoke send <windows-ip> 24801
swift run BarelyRealKmSmoke receive 24801
swift run BarelyRealKmSmoke inject-mouse 20 0
open -a TextEdit
swift run BarelyRealKmSmoke inject-key
```

`capture` requires Accessibility permission for the terminal/app running the command.
The menu-bar app has shortcuts to open Accessibility and Input Monitoring settings.

Minimal Mac-to-Windows dev bridge:

1. On Windows:

   ```powershell
   dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj -- receive 24801
   ```

2. On Mac:

   ```sh
   swift run BarelyRealKmSmoke send <windows-ip> 24801 --peer-left
   ```

`send` defaults to edge mode: Mac stays local until the cursor reaches the configured edge. For your current layout, Windows is left of Mac, so use `--peer-left`; move to the left edge to enter Windows, then move right past the Windows edge to return to Mac. Stop with `Ctrl+C` to restore local control.
Use `--peer-right` when Windows is right of Mac.
Use `--remote` to give Windows control immediately, or `--mirror` only if you intentionally want both machines to move at the same time.

This is raw UDP dev mode. It is only for proving KM capture/transport/inject before TLS pairing is connected.
