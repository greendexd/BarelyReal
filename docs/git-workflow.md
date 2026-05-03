# BarelyReal Git Workflow

Use this flow to work on one shared project from macOS and Windows.

Repository:

```text
https://github.com/greendexd/BarelyReal
```

## First Time on Windows

Install:

- Git for Windows
- .NET 8 SDK

Clone:

```powershell
cd C:\Users\green\Downloads
git clone https://github.com/greendexd/BarelyReal.git
cd BarelyReal
```

Verify:

```powershell
powershell -ExecutionPolicy Bypass -File windows\scripts\verify.ps1
```

Run the Windows app:

```powershell
dotnet run --project windows\App\BarelyReal.App.csproj
```

## First Time on Mac

Clone only if the local folder is missing:

```sh
cd /Users/greendexd
git clone https://github.com/greendexd/BarelyReal.git
cd BarelyReal
```

Verify:

```sh
cd mac
swift build
swift run BarelyRealTests
```

Install the Mac app:

```sh
cd /Users/greendexd/BarelyReal
./mac/scripts/install_app.sh
```

## Daily Sync

Before editing on either machine:

```sh
git pull
```

After editing:

```sh
git status
git add .
git commit -m "Describe the change"
git push
```

Then switch to the other machine and run:

```sh
git pull
```

## Important

- Do not commit `mac/.build`, `mac/dist`, `bin`, `obj`, app bundles, zips, logs, or local secret files.
- Mac runtime behavior must be tested on macOS.
- Windows hooks, input injection, WPF, clipboard, and firewall behavior must be tested on Windows.
- If Windows build fails, copy the full terminal output and send it back to Codex from either machine.
