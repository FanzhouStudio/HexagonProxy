param(
    [ValidateSet('inspect', 'enable', 'disable', 'launch')][string]$Action = 'inspect',
    [string]$ExePath = '',
    [int]$ProxyPort = 7890,
    [string]$PayloadDirectory = '',
    [string]$StateRoot = '',
    [string]$ResultPath = '',
    [switch]$Library
)

$ErrorActionPreference = 'Stop'
$env:PSModulePath = (Join-Path $PSHOME 'Modules') + ';' + $env:PSModulePath
$script:Utf8 = New-Object Text.UTF8Encoding($false)
$script:PayloadHashes = @{
    'version.dll' = '40f037232a180da8dff7611021270549fcc4e208580d8bf0f70bc9975f871b5f'
    'config.template.json' = 'da22147e740b40f155553142da7ff90ba0383421beff8d6cdfd3019c791eeced'
}

function Write-Atomic([string]$Path, [byte[]]$Bytes) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Write-Json([string]$Path, $Value) {
    Write-Atomic $Path $script:Utf8.GetBytes(($Value | ConvertTo-Json -Depth 16))
}

function Get-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Initialize-Target {
    if (-not $ExePath -or -not $StateRoot) { throw 'invalid_path' }
    $script:TargetExe = [IO.Path]::GetFullPath($ExePath)
    if ([IO.Path]::GetFileName($script:TargetExe) -notin @('Antigravity.exe', 'Antigravity IDE.exe')) { throw 'invalid_path' }
    if (-not [IO.File]::Exists($script:TargetExe)) { throw 'not_installed' }
    $script:TargetDirectory = [IO.Path]::GetDirectoryName($script:TargetExe)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $id = [BitConverter]::ToString($sha.ComputeHash($script:Utf8.GetBytes($script:TargetDirectory.ToLowerInvariant()))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $script:InstallationState = Join-Path ([IO.Path]::GetFullPath($StateRoot)) $id
    $script:MarkerPath = Join-Path $script:InstallationState 'state.json'
    $script:BackupDirectory = Join-Path $script:InstallationState 'originals'
    $script:MutexName = 'Local\HexagonProxyAntigravity-' + $id
}

function Assert-X64 {
    $stream = [IO.File]::OpenRead($script:TargetExe)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d -or $stream.Length -lt 64) { throw 'unsupported_architecture' }
        $stream.Position = 0x3c
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset + 6 -gt $stream.Length) { throw 'unsupported_architecture' }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw 'unsupported_architecture' }
    } finally { $reader.Dispose(); $stream.Dispose() }
}

function Get-Running {
    $prefix = $script:TargetDirectory.TrimEnd('\') + '\'
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } catch { $false }
    })
}

function Assert-Stopped {
    if (@(Get-Running).Count -gt 0) { throw 'running' }
}

function Assert-Proxy {
    if ($ProxyPort -lt 1 -or $ProxyPort -gt 65535) { throw 'proxy_unavailable' }
    $client = New-Object Net.Sockets.TcpClient
    try {
        $connection = $client.BeginConnect('127.0.0.1', $ProxyPort, $null, $null)
        try {
            if (-not $connection.AsyncWaitHandle.WaitOne(1500)) { throw 'proxy_unavailable' }
            $client.EndConnect($connection)
        } finally { $connection.AsyncWaitHandle.Close() }
    } catch { throw 'proxy_unavailable' }
    finally { $client.Close() }
}

function Read-State {
    if (-not [IO.File]::Exists($script:MarkerPath)) { return $null }
    try { $state = [IO.File]::ReadAllText($script:MarkerPath) | ConvertFrom-Json } catch { throw 'state_invalid' }
    if ($state.version -ne 1 -or $state.exe_directory -ne $script:TargetDirectory -or -not $state.original -or -not $state.managed) { throw 'state_invalid' }
    return $state
}

function Assert-OwnedFiles($State) {
    foreach ($name in @('version.dll', 'config.json')) {
        $path = Join-Path $script:TargetDirectory $name
        if (-not [IO.File]::Exists($path)) { continue }
        $hash = Get-Hash $path
        $permitted = @([string]$State.managed.$name)
        if ($State.status -ne 'active' -and $State.original.$name.present) { $permitted += [string]$State.original.$name.sha256 }
        if ($State.previous_managed) { $permitted += [string]$State.previous_managed.$name }
        if ($hash -notin $permitted) { throw 'files_changed' }
    }
}

function Restore-Originals($State) {
    # Check every backup before writing any installed file.
    foreach ($name in @('version.dll', 'config.json')) {
        $original = $State.original.$name
        if ($original.present) {
            $backup = Join-Path $script:BackupDirectory $name
            if (-not [IO.File]::Exists($backup) -or (Get-Hash $backup) -ne $original.sha256) { throw 'backup_invalid' }
        }
    }
    foreach ($name in @('version.dll', 'config.json')) {
        $target = Join-Path $script:TargetDirectory $name
        if ($State.original.$name.present) {
            Write-Atomic $target ([IO.File]::ReadAllBytes((Join-Path $script:BackupDirectory $name)))
        } elseif ([IO.File]::Exists($target)) {
            [IO.File]::Delete($target)
        }
    }
    [IO.File]::Delete($script:MarkerPath)
}

function Enable-Proxy {
    Assert-X64
    Assert-Stopped
    Assert-Proxy
    foreach ($name in $script:PayloadHashes.Keys) {
        $path = Join-Path $PayloadDirectory $name
        if (-not [IO.File]::Exists($path) -or (Get-Hash $path) -ne $script:PayloadHashes[$name]) { throw 'payload_invalid' }
    }
    $config = [IO.File]::ReadAllText((Join-Path $PayloadDirectory 'config.template.json')) | ConvertFrom-Json
    $config.proxy.type = 'socks5'
    $config.proxy.host = '127.0.0.1'
    $config.proxy.port = $ProxyPort
    $config.updates.enabled = $false
    $config.updates.allow_insecure_mirrors = $false
    $config.updates.mirrors = @()
    $configBytes = $script:Utf8.GetBytes(($config | ConvertTo-Json -Depth 16))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $configHash = [BitConverter]::ToString($sha.ComputeHash($configBytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $state = Read-State
    $previous = $null
    if ($state) {
        if ($state.status -ne 'active') { throw 'recovery_required' }
        Assert-OwnedFiles $state
        $previous = $state.managed
    } else {
        [void][IO.Directory]::CreateDirectory($script:BackupDirectory)
        $original = @{}
        foreach ($name in @('version.dll', 'config.json')) {
            $path = Join-Path $script:TargetDirectory $name
            $present = [IO.File]::Exists($path)
            $hash = ''
            if ($present) {
                $hash = Get-Hash $path
                Write-Atomic (Join-Path $script:BackupDirectory $name) ([IO.File]::ReadAllBytes($path))
            }
            $original[$name] = @{ present = $present; sha256 = $hash }
        }
        $state = [pscustomobject]@{ version = 1; exe_directory = $script:TargetDirectory; original = $original; managed = $null; status = 'installing'; proxy_port = $ProxyPort; previous_managed = $null }
    }
    $state.status = 'installing'
    $state.previous_managed = $previous
    $state.managed = @{ 'version.dll' = $script:PayloadHashes['version.dll']; 'config.json' = $configHash }
    $state.proxy_port = $ProxyPort
    # Persist recovery information before touching the installation.
    Write-Json $script:MarkerPath $state
    try {
        Write-Atomic (Join-Path $script:TargetDirectory 'config.json') $configBytes
        Write-Atomic (Join-Path $script:TargetDirectory 'version.dll') ([IO.File]::ReadAllBytes((Join-Path $PayloadDirectory 'version.dll')))
        $state.status = 'active'
        $state.previous_managed = $null
        Write-Json $script:MarkerPath $state
    } catch {
        try { Restore-Originals $state } catch { throw 'rollback_failed' }
        throw 'install_failed'
    }
    return @{ ok = $true; message_code = 'enabled' }
}

function Disable-Proxy {
    Assert-Stopped
    $state = Read-State
    if (-not $state) { return @{ ok = $true; message_code = 'disabled' } }
    Assert-OwnedFiles $state
    $state.status = 'restoring'
    Write-Json $script:MarkerPath $state
    Restore-Originals $state
    return @{ ok = $true; message_code = 'disabled' }
}

function Inspect-Proxy {
    $state = Read-State
    $intact = $false
    if ($state) {
        $intact = $state.status -eq 'active'
        foreach ($name in @('version.dll', 'config.json')) {
            $path = Join-Path $script:TargetDirectory $name
            if (-not [IO.File]::Exists($path) -or (Get-Hash $path) -ne $state.managed.$name) { $intact = $false }
        }
    }
    return @{ ok = $true; installed = [bool]$state; intact = $intact; running = @(Get-Running).Count -gt 0; proxy_port = $(if ($state) { $state.proxy_port } else { $ProxyPort }); recovery_required = [bool]($state -and $state.status -ne 'active'); version = '2.4' }
}

function Invoke-ProxyAction {
    Initialize-Target
    $mutex = New-Object Threading.Mutex($false, $script:MutexName)
    $owned = $false
    try {
        try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
        if (-not $owned) { throw 'busy' }
        switch ($Action) {
            'inspect' { return Inspect-Proxy }
            'enable' { return Enable-Proxy }
            'disable' { return Disable-Proxy }
            'launch' {
                if (-not (Read-State)) { throw 'not_enabled' }
                $null = Enable-Proxy
                $process = Start-Process -FilePath $script:TargetExe -WorkingDirectory $script:TargetDirectory -PassThru
                return @{ ok = $true; message_code = 'launched'; pid = $process.Id }
            }
        }
    } finally {
        if ($owned) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

if ($Library) { return }
try { $result = Invoke-ProxyAction }
catch {
    $known = @('invalid_path','not_installed','unsupported_architecture','running','proxy_unavailable','state_invalid','files_changed','backup_invalid','payload_invalid','recovery_required','rollback_failed','install_failed','busy','not_enabled')
    $code = $_.Exception.Message
    if ($code -notin $known) { $code = 'operation_failed' }
    $result = @{ ok = $false; message_code = $code }
}
if ($ResultPath) { Write-Json $ResultPath $result }
else { $result | ConvertTo-Json -Depth 5 }
