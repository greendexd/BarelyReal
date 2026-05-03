# BarelyReal.App

Windows desktop dev UI for the Mac -> Windows receiver.

Run from the repository root:

```powershell
dotnet run --project windows/App/BarelyReal.App.csproj
```

The window starts KM receive on UDP `24801` and clipboard sync on TCP `24802`.
Clipboard sync currently supports UTF-8 text and PNG images.

The Mac command shown by the UI assumes you run it from the repository root on macOS:

```sh
cd mac && swift run BarelyRealKmSmoke send <windows-ip> 24801 0 --peer-left --peer-size 1920x1080
```

The UI is intentionally dev-mode only. Pairing, TLS, tray integration, and full clipboard history
belong to the later app shell once the Core path is stable.
