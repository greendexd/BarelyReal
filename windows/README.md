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

## Normal app launch

Build a desktop-launchable app folder:

```powershell
cd <repo-root>
powershell -ExecutionPolicy Bypass -File windows/scripts/package-app.ps1
```

The publish output is `windows/dist/BarelyReal-win-x64`. Launch `BarelyReal.App.exe` from that folder by double-clicking it. The package is self-contained by default and the project is configured as `WinExe`, so the app opens as a GUI app rather than a console session.

For a smaller framework-dependent folder on a machine that already has .NET Desktop Runtime:

```powershell
powershell -ExecutionPolicy Bypass -File windows/scripts/package-app.ps1 -FrameworkDependent
```

If the app starts but the Mac mouse does not move Windows, allow inbound dev ports once from Administrator PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File windows\scripts\allow-firewall.ps1
```

Then run runtime diagnostics:

```powershell
powershell -ExecutionPolicy Bypass -File windows\scripts\diagnose-runtime.ps1
```

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
