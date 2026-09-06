param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('inspect', 'release')]
    [string]$Action,
    [Parameter(Mandatory = $true)]
    [int]$Port,
    [string]$Pids = '',
    [int]$CallerPid = -1,
    [string]$ProtectedNames = ''
)

$ErrorActionPreference = 'Stop'

function Get-PortOwners([int]$TargetPort) {
    $connections = @(Get-NetTCPConnection -State Listen -LocalPort $TargetPort -ErrorAction SilentlyContinue)
    $ownerIds = @($connections | Select-Object -ExpandProperty OwningProcess -Unique)
    $items = @()
    $protectedSet = @($ProtectedNames -split ';' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
    foreach ($ownerPid in $ownerIds) {
        $name = ''
        try { $name = [string](Get-Process -Id $ownerPid -ErrorAction Stop).ProcessName } catch { $name = 'Unknown' }
        $normalized = $name.Trim().ToLowerInvariant()
        $isProtected = ($ownerPid -le 4) -or ($ownerPid -eq $CallerPid) -or ($protectedSet -contains $normalized)
        $items += [pscustomobject]@{
            pid = [int]$ownerPid
            name = $name
            protected = [bool]$isProtected
        }
    }
    return @($items)
}
function Write-Result($Value) {
    $Value | ConvertTo-Json -Compress -Depth 5
}

if ($Action -eq 'inspect') {
    $owners = @(Get-PortOwners $Port)
    Write-Result ([pscustomobject]@{
        ok = $true
        port = $Port
        occupied = ($owners.Count -gt 0)
        processes = $owners
        message_code = if ($owners.Count -gt 0) { 'occupied' } else { 'free' }
    })
    exit 0
}

$requested = @($Pids -split ',' | ForEach-Object {
    $value = 0
    if ([int]::TryParse($_.Trim(), [ref]$value) -and $value -gt 0) { $value }
})
$current = @(Get-PortOwners $Port)
if ($current.Count -eq 0) {
    Write-Result ([pscustomobject]@{ ok = $true; port = $Port; released = $true; message_code = 'already_free' })
    exit 0
}

$protected = @($current | Where-Object { $_.protected })
if ($protected.Count -gt 0) {
    Write-Result ([pscustomobject]@{ ok = $false; port = $Port; message_code = 'protected'; processes = $protected })
    exit 0
}
$unexpected = @($current | Where-Object { $requested -notcontains [int]$_.pid })
if ($unexpected.Count -gt 0) {
    Write-Result ([pscustomobject]@{
        ok = $false
        port = $Port
        message_code = 'changed'
        processes = $current
    })
    exit 0
}

foreach ($owner in $current) {
    try {
        Stop-Process -Id ([int]$owner.pid) -Force -ErrorAction Stop
    } catch {
        Write-Result ([pscustomobject]@{
            ok = $false
            port = $Port
            message_code = 'kill_failed'
            processes = $current
        })
        exit 0
    }
}

$deadline = [DateTime]::UtcNow.AddSeconds(4)
do {
    Start-Sleep -Milliseconds 120
    $remaining = @(Get-PortOwners $Port)
} while ($remaining.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)
if ($remaining.Count -gt 0) {
    Write-Result ([pscustomobject]@{
        ok = $false
        port = $Port
        released = $false
        message_code = 'still_occupied'
        processes = $remaining
    })
    exit 0
}

Write-Result ([pscustomobject]@{
    ok = $true
    port = $Port
    released = $true
    message_code = 'released'
})
