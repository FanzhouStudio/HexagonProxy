$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\windows_antigravity_proxy_helper.ps1') -Library
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('hexagon-antigravity-tests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$script:checks = 0
$script:simulateRunning = $false
function Assert($Value, [string]$Message) {
    if (-not $Value) { throw "FAIL: $Message" }
    $script:checks++
}
function Assert-Throws([scriptblock]$Operation, [string]$Code) {
    $caught = ''
    try { & $Operation | Out-Null } catch { $caught = $_.Exception.Message }
    Assert ($caught -eq $Code) "expected $Code, received $caught"
}
function Get-Running { if ($script:simulateRunning) { return @([pscustomobject]@{Id=123}) }; return @() }
function New-Fixture([string]$Name, [bool]$WithOriginals = $true) {
    $directory = Join-Path $testRoot $Name
    [void][IO.Directory]::CreateDirectory($directory)
    $script:ExePath = Join-Path $directory 'Antigravity.exe'
    # A PE header fixture only; no downloaded or fake executable is executed.
    $bytes = New-Object byte[] 128
    $bytes[0]=0x4d; $bytes[1]=0x5a; $bytes[0x3c]=64
    $bytes[64]=0x50; $bytes[65]=0x45; $bytes[68]=0x64; $bytes[69]=0x86
    [IO.File]::WriteAllBytes($script:ExePath, $bytes)
    $script:StateRoot = Join-Path $testRoot 'state'
    $script:PayloadDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\third_party\antigravity-proxy'))
    Initialize-Target
    if ($WithOriginals) {
        [IO.File]::WriteAllText((Join-Path $directory 'version.dll'), 'original DLL fixture')
        [IO.File]::WriteAllText((Join-Path $directory 'config.json'), '{"original":"preserve"}')
    }
}
function Assert-Originals {
    Assert ([IO.File]::ReadAllText((Join-Path $script:TargetDirectory 'version.dll')) -eq 'original DLL fixture') 'original DLL restored exactly'
    Assert ([IO.File]::ReadAllText((Join-Path $script:TargetDirectory 'config.json')) -eq '{"original":"preserve"}') 'original config restored exactly'
}

$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
$listener.Start()
$script:ProxyPort = $listener.LocalEndpoint.Port
try {
    New-Fixture 'existing'
    Assert (Enable-Proxy).ok 'enable with original files'
    $inspection = Inspect-Proxy
    Assert ($inspection.installed -and $inspection.intact) 'managed installation is intact'
    $config = [IO.File]::ReadAllText((Join-Path $script:TargetDirectory 'config.json')) | ConvertFrom-Json
    Assert ($config.proxy.port -eq $ProxyPort -and $config.proxy.type -eq 'socks5') 'current port reaches generated SOCKS5 config'
    Assert (-not $config.updates.enabled -and -not $config.updates.allow_insecure_mirrors -and $config.updates.mirrors.Count -eq 0) 'upstream updates and mirrors disabled'
    $script:simulateRunning = $true
    Assert-Throws { Disable-Proxy } 'running'
    Assert-Throws { Enable-Proxy } 'running'
    $script:simulateRunning = $false
    $managedConfig = [IO.File]::ReadAllBytes((Join-Path $script:TargetDirectory 'config.json'))
    [IO.File]::WriteAllText((Join-Path $script:TargetDirectory 'config.json'), 'externally changed')
    Assert-Throws { Disable-Proxy } 'files_changed'
    Assert ([IO.File]::ReadAllText((Join-Path $script:TargetDirectory 'config.json')) -eq 'externally changed') 'external change preserved'
    [IO.File]::WriteAllBytes((Join-Path $script:TargetDirectory 'config.json'), $managedConfig)
    Assert (Disable-Proxy).ok 'disable succeeds'
    Assert-Originals

    New-Fixture 'missing-originals' $false
    Assert (Enable-Proxy).ok 'install when no previous files exist'
    [IO.File]::Delete((Join-Path $script:TargetDirectory 'version.dll'))
    Assert (-not (Inspect-Proxy).intact) 'application update removal detected'
    Assert (Enable-Proxy).ok 'missing managed DLL can be reinstalled'
    Assert (Disable-Proxy).ok 'disable new files'
    Assert (-not [IO.File]::Exists((Join-Path $script:TargetDirectory 'version.dll')) -and -not [IO.File]::Exists((Join-Path $script:TargetDirectory 'config.json'))) 'no originals means deployed files removed'

    New-Fixture 'write-failure'
    $script:originalAtomic = (Get-Item Function:\Write-Atomic).ScriptBlock
    $script:failOnce = $true
    function Write-Atomic([string]$Path, [byte[]]$Bytes) {
        if ($script:failOnce -and $Path -eq (Join-Path $script:TargetDirectory 'version.dll')) {
            $script:failOnce = $false
            throw 'simulated write failure'
        }
        & $script:originalAtomic $Path $Bytes
    }
    Assert-Throws { Enable-Proxy } 'install_failed'
    Assert-Originals
    Assert (-not [IO.File]::Exists($script:MarkerPath)) 'successful rollback clears recovery marker'
    Set-Item -LiteralPath Function:\Write-Atomic -Value $script:originalAtomic

    New-Fixture 'interrupted'
    $null = Enable-Proxy
    $state = Read-State
    $state.status = 'installing'
    Write-Json $script:MarkerPath $state
    [IO.File]::Delete((Join-Path $script:TargetDirectory 'version.dll'))
    Assert (Inspect-Proxy).recovery_required 'interrupted transaction detected'
    Assert-Throws { Enable-Proxy } 'recovery_required'
    Assert (Disable-Proxy).ok 'interrupted deployment restored'
    Assert-Originals

    New-Fixture 'backup-corruption'
    $null = Enable-Proxy
    $backupPath = Join-Path $script:BackupDirectory 'config.json'
    $backupBytes = [IO.File]::ReadAllBytes($backupPath)
    [IO.File]::WriteAllText($backupPath, 'corrupt')
    $beforeHash = Get-Hash (Join-Path $script:TargetDirectory 'version.dll')
    Assert-Throws { Disable-Proxy } 'backup_invalid'
    Assert ((Get-Hash (Join-Path $script:TargetDirectory 'version.dll')) -eq $beforeHash) 'backup validation precedes installed writes'
    [IO.File]::WriteAllBytes($backupPath, $backupBytes)
    $null = Disable-Proxy
    Assert-Originals

    New-Fixture 'payload-corruption'
    $modifiedPayload = Join-Path $testRoot 'modified-payload'
    [void][IO.Directory]::CreateDirectory($modifiedPayload)
    Copy-Item -LiteralPath (Join-Path $PayloadDirectory 'version.dll') -Destination $modifiedPayload
    [IO.File]::WriteAllText((Join-Path $modifiedPayload 'config.template.json'), '{}')
    $script:PayloadDirectory = $modifiedPayload
    Assert-Throws { Enable-Proxy } 'payload_invalid'
    Assert-Originals

    New-Fixture 'port-sync'
    $null = Enable-Proxy
    $second = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $second.Start()
    try {
        $script:ProxyPort = $second.LocalEndpoint.Port
        $null = Enable-Proxy
        Assert ((Read-State).proxy_port -eq $script:ProxyPort) 'port change synchronized'
        # Mock only GUI startup: the fixture executable is never launched.
        function Start-Process { param($FilePath, $WorkingDirectory, [switch]$PassThru); return [pscustomobject]@{Id=321} }
        $script:Action = 'launch'
        Assert ((Invoke-ProxyAction).message_code -eq 'launched') 'launch synchronizes configured proxy before GUI startup'
        $null = Disable-Proxy
        Assert-Originals
    } finally { $second.Stop() }
    $listener.Stop()
    Assert-Throws { Enable-Proxy } 'proxy_unavailable'
    Assert-Originals
    Write-Host "PASS: Antigravity deployment, restore, conflicts, rollback, integrity and port sync ($script:checks checks)"
} finally {
    $listener.Stop()
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected test cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
