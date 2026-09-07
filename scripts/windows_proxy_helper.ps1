param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('enable', 'disable', 'ensure')]
    [string]$Action,
    [Parameter(Mandatory = $true)]
    [string]$StatePath,
    [string]$ProxyServer = '127.0.0.1:7890',
    [string]$ProxyOverride = '<local>'
)

$ErrorActionPreference = 'Stop'
$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

function Get-OptionalRegistryValue([string]$Name) {
    try {
        return @{ Exists = $true; Value = (Get-ItemPropertyValue -LiteralPath $registryPath -Name $Name) }
    } catch {
        return @{ Exists = $false; Value = '' }
    }
}

function Merge-ProxyOverride([string]$Required, [string]$Existing) {
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($source in @($Required, $Existing)) {
        foreach ($entry in ([string]$source -split ';')) {
            $value = $entry.Trim()
            if ($value -and -not ($items -contains $value)) { $items.Add($value) }
        }
    }
    return ($items -join ';')
}

if ($Action -in @('enable', 'ensure')) {
    $enable = Get-OptionalRegistryValue 'ProxyEnable'
    $server = Get-OptionalRegistryValue 'ProxyServer'
    $override = Get-OptionalRegistryValue 'ProxyOverride'
    if ($Action -eq 'ensure' -and $enable.Exists -and [int]$enable.Value -eq 1 -and [string]$server.Value -eq $ProxyServer) { exit 0 }
    if (-not (Test-Path -LiteralPath $StatePath)) { @{
        ProxyEnable = if ($enable.Exists) { [int]$enable.Value } else { 0 }
        ProxyServerExists = [bool]$server.Exists
        ProxyServer = [string]$server.Value
        ProxyOverrideExists = [bool]$override.Exists
        ProxyOverride = [string]$override.Value
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $StatePath -Encoding UTF8 }
    $existingOverride = if ($override.Exists) { [string]$override.Value } else { '' }
    $effectiveOverride = Merge-ProxyOverride $ProxyOverride $existingOverride
    Set-ItemProperty -LiteralPath $registryPath -Name 'ProxyServer' -Type String -Value $ProxyServer
    Set-ItemProperty -LiteralPath $registryPath -Name 'ProxyOverride' -Type String -Value $effectiveOverride
    Set-ItemProperty -LiteralPath $registryPath -Name 'ProxyEnable' -Type DWord -Value 1
} else {
    if (Test-Path -LiteralPath $StatePath) {
        $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
        Set-ItemProperty -LiteralPath $registryPath -Name 'ProxyEnable' -Type DWord -Value ([int]$state.ProxyEnable)
        if ([bool]$state.ProxyServerExists) {
            Set-ItemProperty -LiteralPath $registryPath -Name 'ProxyServer' -Type String -Value ([string]$state.ProxyServer)
        } else {
            Remove-ItemProperty -LiteralPath $registryPath -Name 'ProxyServer' -ErrorAction SilentlyContinue
        }
        if ([bool]$state.ProxyOverrideExists) {
            Set-ItemProperty -LiteralPath $registryPath -Name 'ProxyOverride' -Type String -Value ([string]$state.ProxyOverride)
        } else {
            Remove-ItemProperty -LiteralPath $registryPath -Name 'ProxyOverride' -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    } else {
        Set-ItemProperty -LiteralPath $registryPath -Name 'ProxyEnable' -Type DWord -Value 0
    }
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class HexagonInternetSettings {
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int option, IntPtr buffer, int length);
}
'@
[HexagonInternetSettings]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
[HexagonInternetSettings]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
