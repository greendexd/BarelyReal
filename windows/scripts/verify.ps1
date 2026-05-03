param(
    [switch]$NoRun,
    [switch]$NoSmoke
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WindowsDir = Resolve-Path (Join-Path $ScriptDir "..")
$RepoRoot = Resolve-Path (Join-Path $WindowsDir "..")
$LogDir = Join-Path $WindowsDir "artifacts"
$LogPath = Join-Path $LogDir "verify-windows.log"
$LocalDotnet = Join-Path $env:USERPROFILE ".dotnet"

if (Test-Path (Join-Path $LocalDotnet "dotnet.exe")) {
    $env:DOTNET_ROOT = $LocalDotnet
    $env:PATH = "$LocalDotnet;$env:PATH"
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Step($Name, $ScriptBlock) {
    Write-Host ""
    Write-Host "==> $Name" -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    & $ScriptBlock 2>&1 | Tee-Object -FilePath $LogPath -Append
    if ($global:LASTEXITCODE -ne 0) {
        throw "Step '$Name' failed with exit code $global:LASTEXITCODE"
    }
}

Set-Content -Path $LogPath -Value "BarelyReal Windows verify $(Get-Date -Format o)"

Step "Environment" {
    Write-Host "RepoRoot: $RepoRoot"
    Write-Host "WindowsDir: $WindowsDir"
    dotnet --info
}

Step "Restore" {
    dotnet restore (Join-Path $WindowsDir "BarelyReal.sln")
}

Step "Build" {
    dotnet build (Join-Path $WindowsDir "BarelyReal.sln") --no-restore -warnaserror
}

if (-not $NoRun) {
    Step "Tests" {
        dotnet run --project (Join-Path $WindowsDir "Tests/BarelyReal.Tests.csproj") --no-build
    }
}

if (-not $NoSmoke) {
    Step "UDP smoke" {
        dotnet run --project (Join-Path $WindowsDir "Tools/KmSmoke/KmSmoke.csproj") --no-build -- udp-loopback
    }
}

Write-Host ""
Write-Host "Windows verification complete. Log: $LogPath" -ForegroundColor Green
