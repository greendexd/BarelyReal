param(
    [int]$KmPort = 24801,
    [int]$ClipboardPort = 24802,
    [ValidateSet("Private", "Domain", "Public", "Any")]
    [string]$Profile = "Private"
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host "Run this from PowerShell as Administrator." -ForegroundColor Red
    Write-Host "Then execute:" -ForegroundColor Yellow
    Write-Host "powershell -ExecutionPolicy Bypass -File windows\scripts\allow-firewall.ps1" -ForegroundColor Yellow
    exit 1
}

$rules = @(
    @{ Name = "BarelyReal KM UDP $KmPort"; Protocol = "UDP"; Port = $KmPort },
    @{ Name = "BarelyReal Clipboard TCP $ClipboardPort"; Protocol = "TCP"; Port = $ClipboardPort }
)

foreach ($rule in $rules) {
    Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule

    New-NetFirewallRule `
        -DisplayName $rule.Name `
        -Direction Inbound `
        -Action Allow `
        -Protocol $rule.Protocol `
        -LocalPort $rule.Port `
        -Profile $Profile | Out-Null

    Write-Host "Allowed inbound $($rule.Protocol) port $($rule.Port) on $Profile profile." -ForegroundColor Green
}

Write-Host "BarelyReal firewall rules are ready." -ForegroundColor Green
