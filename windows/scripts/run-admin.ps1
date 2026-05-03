param(
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WindowsDir = Resolve-Path (Join-Path $ScriptDir "..")
$RepoRoot = Resolve-Path (Join-Path $WindowsDir "..")
$LocalDotnet = Join-Path $env:USERPROFILE ".dotnet"

if (Test-Path (Join-Path $LocalDotnet "dotnet.exe")) {
    $env:DOTNET_ROOT = $LocalDotnet
    $env:PATH = "$LocalDotnet;$env:PATH"
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath
    )
    if ($NoBuild) {
        $args += "-NoBuild"
    }

    Start-Process -FilePath "powershell.exe" -ArgumentList $args -Verb RunAs -WindowStyle Normal
    Write-Host "Requested administrator launch for BarelyReal." -ForegroundColor Cyan
    exit 0
}

$AppExe = Join-Path $WindowsDir "App/bin/Debug/net8.0-windows/BarelyReal.App.exe"

Get-Process -Name "BarelyReal.App" -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $AppExe } |
    Stop-Process -Force

if (-not $NoBuild) {
    dotnet build (Join-Path $WindowsDir "App/BarelyReal.App.csproj")
}

if (-not (Test-Path $AppExe)) {
    throw "App executable not found: $AppExe"
}

Start-Process -FilePath $AppExe -WorkingDirectory $RepoRoot
Write-Host "BarelyReal started as Administrator." -ForegroundColor Green
