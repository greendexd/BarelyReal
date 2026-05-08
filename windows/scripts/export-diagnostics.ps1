param(
    [int]$ControlPort = 24800,
    [int]$KmPort = 24801,
    [int]$ClipboardPort = 24802
)

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WindowsDir = Resolve-Path (Join-Path $ScriptDir "..")
$RepoRoot = Resolve-Path (Join-Path $WindowsDir "..")
$LogDir = Join-Path $WindowsDir "artifacts"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$OutPath = Join-Path $LogDir "diagnostics-windows-$Stamp.txt"
$DiagScript = Join-Path $ScriptDir "diagnose-runtime.ps1"
$VerifyLog = Join-Path $LogDir "verify-windows.log"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

Set-Content -Path $OutPath -Value "BarelyReal Windows diagnostics $(Get-Date -Format o)"
Add-Content -Path $OutPath -Value ""
Add-Content -Path $OutPath -Value "== Repository =="
Add-Content -Path $OutPath -Value "RepoRoot: $RepoRoot"
try {
    git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>&1 | Add-Content -Path $OutPath
    git -C $RepoRoot rev-parse --short HEAD 2>&1 | Add-Content -Path $OutPath
    git -C $RepoRoot status --short 2>&1 | Add-Content -Path $OutPath
} catch {}
Add-Content -Path $OutPath -Value ""

& $DiagScript -ControlPort $ControlPort -KmPort $KmPort -ClipboardPort $ClipboardPort 2>&1 |
    Tee-Object -FilePath $OutPath -Append

Add-Content -Path $OutPath -Value ""
Add-Content -Path $OutPath -Value "== Recent verify log =="
if (Test-Path $VerifyLog) {
    Get-Content $VerifyLog -Tail 120 | Add-Content -Path $OutPath
} else {
    Add-Content -Path $OutPath -Value "No verify log found."
}

Add-Content -Path $OutPath -Value ""
Add-Content -Path $OutPath -Value "Clipboard contents, keystrokes, and file bytes are intentionally not included."

Write-Host "Diagnostics written to $OutPath" -ForegroundColor Green
