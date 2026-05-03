# BarelyReal Windows

Windows-specific verification starts here.

```powershell
cd <repo-root>
powershell -ExecutionPolicy Bypass -File windows/scripts/verify.ps1
```

The script runs:

- `dotnet --info`
- `dotnet restore windows/BarelyReal.sln`
- `dotnet build windows/BarelyReal.sln --no-restore -warnaserror` (Core, Tests, KmSmoke, App)
- `dotnet run --project windows/Tests/BarelyReal.Tests.csproj --no-build`
- `dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj --no-build -- udp-loopback`

Logs are written to `windows/artifacts/verify-windows.log`.

Manual KM smoke after the build is green:

```powershell
dotnet run --project windows/App/BarelyReal.App.csproj
dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj -- capture 10
dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj -- receive 24801 --clipboard-peer <mac-ip>
dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj -- send <mac-ip> 24801
dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj -- inject-mouse 20 0
notepad
dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj -- inject-key
```

Minimal Mac-to-Windows dev bridge:

1. On Windows:

   ```powershell
   dotnet run --project windows/App/BarelyReal.App.csproj
   ```

2. On Mac, use the app UI or run the CLI from the repo root:

   ```sh
   cd mac
   swift run BarelyRealKmSmoke send <windows-ip> 24801 0 --peer-left --peer-size 1920x1080
   ```

The Windows app starts both raw UDP KM receive and TCP clipboard sync. Clipboard sync currently supports text, PNG images, and file bundles.
This is dev mode only, before TLS pairing and the final tray app flow are connected.

Windows -> Mac mode:

1. On Mac, open BarelyReal and select `Windows → Mac`.
2. On Windows, select `Windows → Mac (send)`, enter the Mac IP/size, and press Start.
3. Move the Windows cursor past the configured edge to enter the Mac.

Use `Tools/KmSmoke` for the current dev receiver:

```powershell
dotnet run --project windows\Tools\KmSmoke\KmSmoke.csproj -- receive 24801 --clipboard-peer <mac-ip>
```
