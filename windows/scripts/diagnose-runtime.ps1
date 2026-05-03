param(
    [int]$KmPort = 24801,
    [int]$ClipboardPort = 24802
)

$ErrorActionPreference = "Continue"

Write-Host "== BarelyReal runtime diagnostics ==" -ForegroundColor Cyan
Write-Host ""

Write-Host "Local IPv4 addresses:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -notlike "127.*" -and
        $_.IPAddress -notlike "169.254.*" -and
        $_.PrefixOrigin -ne "WellKnown"
    } |
    Sort-Object InterfaceAlias, IPAddress |
    Format-Table InterfaceAlias, IPAddress, PrefixLength -AutoSize

Write-Host ""
Write-Host "BarelyReal processes:" -ForegroundColor Cyan
Get-Process |
    Where-Object { $_.ProcessName -like "BarelyReal*" } |
    Select-Object Id, ProcessName, Path |
    Format-Table -AutoSize

Write-Host ""
Write-Host "Listening UDP $KmPort:" -ForegroundColor Cyan
Get-NetUDPEndpoint -LocalPort $KmPort -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, OwningProcess |
    Format-Table -AutoSize

Write-Host ""
Write-Host "Listening TCP $ClipboardPort:" -ForegroundColor Cyan
Get-NetTCPConnection -LocalPort $ClipboardPort -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, State, OwningProcess |
    Format-Table -AutoSize

Write-Host ""
Write-Host "BarelyReal firewall rules:" -ForegroundColor Cyan
$rules = Get-NetFirewallRule -DisplayName "BarelyReal*" -ErrorAction SilentlyContinue
if ($rules) {
    $rules | Format-Table DisplayName, Enabled, Direction, Action, Profile -AutoSize
    $rules | Get-NetFirewallPortFilter | Format-Table Protocol, LocalPort -AutoSize
} else {
    Write-Host "No BarelyReal firewall rules found." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Expected for Mac -> Windows:" -ForegroundColor Cyan
Write-Host "- Windows app mode: Mac -> Windows"
Write-Host "- App status: Running"
Write-Host "- UDP $KmPort is listening"
Write-Host "- Firewall allows inbound UDP $KmPort"
Write-Host "- Mac peer IP is one of the Windows Wi-Fi/LAN IPv4 addresses above, not VPN"
