param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [switch]$FrameworkDependent
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WindowsDir = Resolve-Path (Join-Path $ScriptDir "..")
$RepoRoot = Resolve-Path (Join-Path $WindowsDir "..")
$ProjectPath = Join-Path $WindowsDir "App/BarelyReal.App.csproj"
$DistRoot = Join-Path $WindowsDir "dist"
$PublishDir = Join-Path $DistRoot "BarelyReal-$Runtime"
$LocalDotnet = Join-Path $env:USERPROFILE ".dotnet"

if (Test-Path (Join-Path $LocalDotnet "dotnet.exe")) {
    $env:DOTNET_ROOT = $LocalDotnet
    $env:PATH = "$LocalDotnet;$env:PATH"
}

if (Test-Path $PublishDir) {
    Remove-Item -Recurse -Force $PublishDir
}

New-Item -ItemType Directory -Force -Path $PublishDir | Out-Null

$selfContainedValue = if ($FrameworkDependent) { "false" } else { "true" }

dotnet publish $ProjectPath `
    --configuration $Configuration `
    --runtime $Runtime `
    --self-contained:$selfContainedValue `
    --output $PublishDir `
    -p:PublishSingleFile=false `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -warnaserror

$launcherPath = Join-Path $PublishDir "Launch BarelyReal.cmd"
$readmePath = Join-Path $PublishDir "README.txt"

Set-Content -Path $launcherPath -Encoding ASCII -Value @"
@echo off
cd /d "%~dp0"
start "" "BarelyReal.App.exe"
"@

Set-Content -Path $readmePath -Encoding ASCII -Value @"
BarelyReal Windows app

Double-click BarelyReal.App.exe to launch the GUI app.
If SmartScreen prompts, choose More info, then Run anyway.
This package is self-contained by default, so it does not need dotnet run.

Package source:
$RepoRoot

Build:
dotnet publish $ProjectPath --configuration $Configuration --runtime $Runtime --self-contained:$selfContainedValue --output $PublishDir -warnaserror
"@

Write-Host ""
Write-Host "Packaged BarelyReal Windows app:" -ForegroundColor Green
Write-Host "  $PublishDir"
Write-Host "Launch by double-clicking BarelyReal.App.exe."
