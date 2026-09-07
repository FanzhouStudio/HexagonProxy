param(
    [ValidateSet('inspect', 'switch', 'launch', 'capture', 'import', 'prepare', 'usage', 'recover', 'login')]
    [string]$Action = 'inspect',
    [string]$CodexHome = '',
    [string]$CurrentSnapshot = '',
    [string]$ActiveHome = '',
    [string]$ImportPath = '',
    [string]$IndexPath = '',
    [string]$PendingIndex = '',
    [string]$ExpectedProfileId = '',
    [string]$RelatedHomes = '',
    [string]$ResultPath = '',
    [switch]$Library
)

$ErrorActionPreference = 'Stop'
# Godot may inherit PowerShell 7's module path; load Windows PowerShell's own
# modules first when invoked through OS.execute rather than a PowerShell host.
$env:PSModulePath = (Join-Path $PSHOME 'Modules') + ';' + $env:PSModulePath
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-ActiveHome {
    if ($ActiveHome) { return [IO.Path]::GetFullPath($ActiveHome) }
    if ($env:CODEX_HOME) { return [IO.Path]::GetFullPath($env:CODEX_HOME) }
    return Join-Path $env:USERPROFILE '.codex'
}

function Write-Atomic([string]$Path, [byte[]]$Bytes) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllBytes($temp, $Bytes)
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temp, $Path) }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

function Write-JsonFile($Path, $Value) {
    Write-Atomic $Path $script:Utf8.GetBytes(($Value | ConvertTo-Json -Depth 40))
}
function Read-JsonFile($Path) { return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json) }

function Assert-DifferentDirectories($First, $Second) {
    $a = [IO.Path]::GetFullPath($First).TrimEnd('\', '/')
    $b = [IO.Path]::GetFullPath($Second).TrimEnd('\', '/')
    if ($a.Equals($b, [StringComparison]::OrdinalIgnoreCase)) { throw 'unsafe_path' }
}

# Only authentication/configuration are snapshotted. Never copy histories,
# databases, skills, or the desktop application's browser storage.
function Save-Snapshot($Source, $Target) {
    Assert-DifferentDirectories $Source $Target
    [void][IO.Directory]::CreateDirectory($Target)
    foreach ($name in @('auth.json', 'config.toml')) {
        $from = Join-Path $Source $name
        $to = Join-Path $Target $name
        if ([IO.File]::Exists($from)) { Write-Atomic $to ([IO.File]::ReadAllBytes($from)) }
        elseif ([IO.File]::Exists($to)) { [IO.File]::Delete($to) }
    }
    Write-SnapshotManifest $Target
}
function Write-SnapshotManifest($Path) {
    $metadata = @{ version = 1; captured_at = [DateTime]::UtcNow.ToString('o') }
    foreach ($name in @('auth', 'config')) {
        $file = Join-Path $Path $(if ($name -eq 'auth') { 'auth.json' } else { 'config.toml' })
        $metadata[$name + '_present'] = [IO.File]::Exists($file)
        if ($metadata[$name + '_present']) { $metadata[$name + '_sha256'] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash }
    }
    Write-JsonFile (Join-Path $Path 'snapshot.json') $metadata
}
function Assert-Snapshot($Path) {
    $marker = Join-Path $Path 'snapshot.json'
    if (-not [IO.File]::Exists($marker)) {
        # v3 account snapshots predate manifests but must contain credentials.
        if (-not [IO.File]::Exists((Join-Path $Path 'auth.json'))) { throw 'snapshot_missing' }
        return
    }
    $metadata = Read-JsonFile $marker
    foreach ($name in @('auth', 'config')) {
        $file = Join-Path $Path $(if ($name -eq 'auth') { 'auth.json' } else { 'config.toml' })
        if ($metadata.($name + '_present') -and -not [IO.File]::Exists($file)) { throw 'snapshot_missing' }
        if ($metadata.($name + '_sha256') -and (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $metadata.($name + '_sha256')) { throw 'snapshot_missing' }
    }
}
function Restore-Snapshot($Source, $Target) {
    Assert-DifferentDirectories $Source $Target
    Assert-Snapshot $Source
    foreach ($name in @('auth.json', 'config.toml')) {
        $from = Join-Path $Source $name
        $to = Join-Path $Target $name
        if ([IO.File]::Exists($from)) { Write-Atomic $to ([IO.File]::ReadAllBytes($from)) }
        elseif ([IO.File]::Exists($to)) { [IO.File]::Delete($to) }
    }
}

# JWT claims are display metadata, never proof that authentication is valid.
function Read-Claims([string]$Token) {
    try {
        $part = $Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
        $part = $part.PadRight($part.Length + (4 - $part.Length % 4) % 4, '=')
        return ($script:Utf8.GetString([Convert]::FromBase64String($part)) | ConvertFrom-Json)
    } catch { return $null }
}
function Get-AuthInfo($Auth) {
    if ($null -eq $Auth -or $Auth -is [array] -or $Auth -is [string]) { throw 'invalid_auth' }
    if ($Auth.OPENAI_API_KEY -is [string] -and -not [string]::IsNullOrWhiteSpace($Auth.OPENAI_API_KEY)) {
        return @{ login_present = $true; auth_kind = 'api'; email = ''; account_id = ''; plan = 'API' }
    }
    foreach ($name in @('access_token', 'id_token', 'refresh_token')) {
        if ($Auth.tokens.$name -isnot [string] -or [string]::IsNullOrWhiteSpace($Auth.tokens.$name)) { throw 'missing_tokens' }
    }
    $claims = Read-Claims ([string]$Auth.tokens.id_token)
    $access = Read-Claims ([string]$Auth.tokens.access_token)
    $account = [string]$Auth.tokens.account_id
    if (-not $account) { $account = [string]$access.'https://api.openai.com/auth'.chatgpt_account_id }
    if (-not $account) { $account = [string]$claims.'https://api.openai.com/auth'.chatgpt_account_id }
    return @{
        login_present = $true; auth_kind = 'chatgpt'; account_id = $account
        email = [string]$claims.email; plan = [string]$claims.'https://api.openai.com/auth'.chatgpt_plan_type
    }
}
function Get-HomeInfo($Path) {
    $authPath = Join-Path $Path 'auth.json'
    if (-not [IO.File]::Exists($authPath)) { return @{ login_present = $false } }
    try { return Get-AuthInfo (Read-JsonFile $authPath) }
    catch { return @{ login_present = $false; auth_error = 'missing_tokens' } }
}

function Test-SameAccount($First, $Second) {
    $a = Get-AuthInfo $First; $b = Get-AuthInfo $Second
    if ($a.auth_kind -eq 'api' -or $b.auth_kind -eq 'api') {
        return ($a.auth_kind -eq 'api' -and $b.auth_kind -eq 'api' -and $First.OPENAI_API_KEY -ceq $Second.OPENAI_API_KEY)
    }
    return ($a.account_id -and $a.account_id -eq $b.account_id -and
        (-not $a.email -or -not $b.email -or $a.email -eq $b.email))
}

# Account credentials are durable records, unlike exact rollback snapshots.
# A logout/missing live file must never erase a saved authorization.
function Sync-AccountCredentials($Source, $Target) {
    Assert-DifferentDirectories $Source $Target
    $sourceFile = Join-Path $Source 'auth.json'
    if (-not [IO.File]::Exists($sourceFile)) { return }
    $bytes = [IO.File]::ReadAllBytes($sourceFile)
    $auth = $script:Utf8.GetString($bytes) | ConvertFrom-Json
    $null = Get-AuthInfo $auth
    $targetFile = Join-Path $Target 'auth.json'
    if ([IO.File]::Exists($targetFile)) {
        if (-not (Test-SameAccount $auth (Read-JsonFile $targetFile))) { throw 'state_changed' }
    }
    Write-Atomic $targetFile $bytes
    Write-SnapshotManifest $Target
}

function Sync-AccountState($Source, $Target) {
    Sync-AccountCredentials $Source $Target
    $config = Join-Path $Source 'config.toml'
    if ([IO.File]::Exists($config)) { Write-Atomic (Join-Path $Target 'config.toml') ([IO.File]::ReadAllBytes($config)) }
    Write-SnapshotManifest $Target
}

function Get-AuthFreshness($Auth) {
    $score = 0L
    $claims = Read-Claims ([string]$Auth.tokens.access_token)
    if ($claims -and $claims.exp) { $score = [Math]::Max($score, [long]$claims.exp) }
    if ($Auth.last_refresh) {
        $timestamp = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse([string]$Auth.last_refresh, [ref]$timestamp)) {
            $score = [Math]::Max($score, $timestamp.ToUnixTimeSeconds())
        } elseif ([long]::TryParse([string]$Auth.last_refresh, [ref]$score)) {}
    }
    return $score
}

function Get-RelatedHomeList {
    if (-not $RelatedHomes) { return @() }
    return @($RelatedHomes.Split('|', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { [IO.Path]::GetFullPath($_) } | Select-Object -Unique)
}

function Sync-LatestAccountCredentials($Path) {
    $reference = Read-JsonFile (Join-Path $Path 'auth.json')
    $null = Get-AuthInfo $reference
    $bestPath = [IO.Path]::GetFullPath($Path)
    $bestAuth = $reference
    $bestScore = Get-AuthFreshness $reference
    foreach ($candidatePath in @((Get-ActiveHome)) + @(Get-RelatedHomeList)) {
        $candidateFile = Join-Path $candidatePath 'auth.json'
        if (-not [IO.File]::Exists($candidateFile)) { continue }
        try {
            $candidate = Read-JsonFile $candidateFile
            if (-not (Test-SameAccount $reference $candidate)) { continue }
        } catch { continue }
        $score = Get-AuthFreshness $candidate
        if ($score -gt $bestScore) { $bestPath = $candidatePath; $bestAuth = $candidate; $bestScore = $score }
    }
    if (-not [IO.Path]::GetFullPath($bestPath).Equals([IO.Path]::GetFullPath($Path), [StringComparison]::OrdinalIgnoreCase)) {
        Sync-AccountCredentials $bestPath $Path
        $bestAuth = Read-JsonFile (Join-Path $Path 'auth.json')
    }
    return $bestAuth
}

function Publish-AccountCredentials($Source) {
    $sourceAuth = Read-JsonFile (Join-Path $Source 'auth.json')
    foreach ($candidatePath in @(Get-RelatedHomeList)) {
        $candidateFile = Join-Path $candidatePath 'auth.json'
        if (-not [IO.File]::Exists($candidateFile)) { continue }
        try {
            $candidate = Read-JsonFile $candidateFile
            if (Test-SameAccount $sourceAuth $candidate) { Sync-AccountCredentials $Source $candidatePath }
        } catch { continue }
    }
}

function Test-AccessExpired($Auth) {
    $claims = Read-Claims ([string]$Auth.tokens.access_token)
    return ($claims -and $claims.exp -and [long]$claims.exp -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 60)
}

function Update-AccountTokens($Path, [bool]$Force = $false) {
    $file = Join-Path $Path 'auth.json'
    $auth = Sync-LatestAccountCredentials $Path
    $info = Get-AuthInfo $auth
    if ($info.auth_kind -eq 'api') { return $auth }
    $live = Get-ActiveHome
    $liveFile = Join-Path $live 'auth.json'
    $samePath = [IO.Path]::GetFullPath($Path).TrimEnd('\') -eq [IO.Path]::GetFullPath($live).TrimEnd('\')
    $active = $false
    if ([IO.File]::Exists($liveFile)) {
        $current = Read-JsonFile $liveFile
        $active = Test-SameAccount $auth $current
        if ($active -and -not $samePath) {
            $auth = Sync-LatestAccountCredentials $Path
        }
    }
    if (-not $Force -and -not (Test-AccessExpired $auth)) {
        Publish-AccountCredentials $Path
        return $auth
    }
    # Do not race the desktop app's rotating refresh token. It owns active auth.
    if ($active -and @(Get-CodexProcesses).Count -gt 0) { throw 'auth_refresh_pending' }
    $before = [IO.File]::ReadAllText($file)
    try {
        $response = Invoke-RestMethod -Uri 'https://auth.openai.com/oauth/token' -Method Post -ContentType 'application/x-www-form-urlencoded' -Body @{
            grant_type = 'refresh_token'; refresh_token = $auth.tokens.refresh_token
            client_id = 'app_EMoamEEZ73f0CkXaXp7hrann'
        } -TimeoutSec 18 -MaximumRedirection 0
    } catch {
        $status = 0
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        if ($status -in @(400, 401)) { throw 'reauthorization_required' }
        throw 'token_refresh_failed'
    }
    if (-not ($response.access_token -is [string]) -or -not $response.access_token) { throw 'token_refresh_failed' }
    $updated = $before | ConvertFrom-Json
    $updated.tokens.access_token = $response.access_token
    if ($response.id_token) { $updated.tokens.id_token = $response.id_token }
    if ($response.refresh_token) { $updated.tokens.refresh_token = $response.refresh_token }
    $updated | Add-Member -NotePropertyName last_refresh -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    if (-not (Test-SameAccount $auth $updated)) { throw 'state_changed' }
    # Store the rotated token before updating any secondary copy. Never retry a
    # consumed refresh token merely because a later usage request failed.
    if ([IO.File]::ReadAllText($file) -ne $before) { throw 'state_changed' }
    Write-JsonFile $file $updated
    if (-not $samePath) { Write-SnapshotManifest $Path }
    if ($active -and -not $samePath -and [IO.File]::Exists($liveFile)) {
        $latest = Read-JsonFile $liveFile
        if (Test-SameAccount $auth $latest) {
            if ($latest.tokens.refresh_token -eq $auth.tokens.refresh_token) { Write-JsonFile $liveFile $updated }
        }
    }
    Publish-AccountCredentials $Path
    return $updated
}

function Get-CodexCliExecutable {
    $candidates = @()
    # Explorer-launched apps do not inherit Codex's augmented PATH. The Store
    # resources executable can also be present but denied execution (Win32 5).
    $binRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    if (Test-Path -LiteralPath $binRoot) {
        foreach ($dir in @(Get-ChildItem -LiteralPath $binRoot -Directory | Sort-Object LastWriteTime -Descending)) {
            $candidates += Join-Path $dir.FullName 'codex.exe'
        }
    }
    $cli = Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($cli) { $candidates += $cli.Source }
    $desktop = Get-CodexExecutable
    if ($desktop) { $candidates += Join-Path (Split-Path $desktop) 'resources\codex.exe' }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not [IO.File]::Exists($candidate)) { continue }
        $probe = $null
        try {
            $info = New-Object Diagnostics.ProcessStartInfo
            $info.FileName = $candidate
            $info.Arguments = '--version'
            $info.UseShellExecute = $false
            $info.CreateNoWindow = $true
            $info.RedirectStandardOutput = $true
            $info.RedirectStandardError = $true
            $probe = [Diagnostics.Process]::Start($info)
            $stdout = $probe.StandardOutput.ReadToEndAsync()
            $stderr = $probe.StandardError.ReadToEndAsync()
            if ($probe.WaitForExit(5000) -and $probe.ExitCode -eq 0 -and $stdout.Result -match '^codex-cli\s') {
                return $candidate
            }
        } catch {
            # Try the next official installation; do not expose process output.
        } finally {
            if ($probe) {
                if (-not $probe.HasExited) { $probe.Kill() }
                $probe.Dispose()
            }
        }
    }
    throw 'cli_missing'
}

function Invoke-Login {
    Assert-DifferentDirectories (Get-ActiveHome) $CodexHome
    if ([IO.File]::Exists((Join-Path $CodexHome 'auth.json'))) { throw 'state_changed' }
    $exe = Get-CodexCliExecutable
    [void][IO.Directory]::CreateDirectory($CodexHome)
    Write-Atomic (Join-Path $CodexHome 'config.toml') $script:Utf8.GetBytes('cli_auth_credentials_store = "file"')
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $exe
    $start.Arguments = 'login'
    # Environment isolation and redirected streams require direct process launch.
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['CODEX_HOME'] = $CodexHome
    $process = [Diagnostics.Process]::Start($start)
    try {
        $streams = @($process.StandardOutput, $process.StandardError)
        $tasks = @($streams[0].ReadLineAsync(), $streams[1].ReadLineAsync())
        $deadline = [DateTime]::UtcNow.AddMinutes(15)
        $browserOpened = $false
        while (-not $process.HasExited) {
            for ($i = 0; $i -lt 2; $i++) {
                if ($null -ne $tasks[$i] -and $tasks[$i].IsCompleted) {
                    $line = $tasks[$i].GetAwaiter().GetResult()
                    if ($null -ne $line) {
                        # Hidden CLI processes cannot reliably open the browser themselves.
                        # Never pass arbitrary CLI output to the shell or include it in errors.
                        if (-not $browserOpened -and $line -match '(https://auth\.openai\.com/oauth/authorize\?[^\s]+)') {
                            $browser = New-Object Diagnostics.ProcessStartInfo
                            $browser.FileName = $Matches[1]
                            $browser.UseShellExecute = $true
                            try {
                                [void][Diagnostics.Process]::Start($browser)
                                $browserOpened = $true
                                if ($ResultPath) { Write-JsonFile ($ResultPath + '.progress') @{ browser_opened = $true } }
                            }
                            catch { throw 'browser_failed' }
                        }
                        $tasks[$i] = $streams[$i].ReadLineAsync()
                    } else { $tasks[$i] = $null }
                }
            }
            if ([DateTime]::UtcNow -gt $deadline) { throw 'login_timeout' }
            Start-Sleep -Milliseconds 50
        }
        if ($process.ExitCode -ne 0) { throw 'login_failed' }
        $info = Get-HomeInfo $CodexHome
        if (-not $info.login_present) { throw 'missing_tokens' }
        Write-SnapshotManifest $CodexHome
        Publish-AccountCredentials $CodexHome
        return @{ ok = $true; account = $info }
    } finally {
        if (-not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}

# Replace complete top-level TOML statements, respecting comments, multiline
# strings, arrays, inline tables and quoted keys. Retain all unrelated text.
function Set-RootConfig([string]$Text, [hashtable]$Settings, [hashtable]$Previous = $null) {
    $result = New-Object Text.StringBuilder
    $start = 0; $i = 0; $quote = ''; $depth = 0; $comment = $false
    while ($i -lt $Text.Length) {
        if ($i -eq $start -and $quote -eq '' -and $depth -eq 0) {
            if ($Text.Substring($i) -match '^[ \t]*\[') { break }
        }
        $ch = [string]$Text[$i]
        if ($comment) { if ($ch -eq "`n") { $comment = $false } }
        elseif ($quote) {
            if ($quote.Contains('"') -and $ch -eq '\') { $i += 2; continue }
            if ($Text.Substring($i).StartsWith($quote)) { $i += $quote.Length; $quote = ''; continue }
        } elseif ($ch -eq '#') { $comment = $true }
        elseif ($ch -eq '"' -or $ch -eq "'") {
            $quote = $ch
            if ($Text.Substring($i).StartsWith($ch + $ch + $ch)) { $quote = $ch + $ch + $ch }
            $i += $quote.Length; continue
        } elseif ($ch -eq '[' -or $ch -eq '{') { $depth++ }
        elseif ($ch -eq ']' -or $ch -eq '}') { $depth-- }
        if ($ch -eq "`n" -and -not $quote -and $depth -eq 0) {
            $statement = $Text.Substring($start, $i - $start + 1)
            $replace = $false
            foreach ($key in $Settings.Keys) {
                $escaped = [regex]::Escape($key)
                if ($statement -match ('^\s*(?:' + $escaped + '|"' + $escaped + '"|\x27' + $escaped + '\x27)\s*=')) {
                    if ($null -ne $Previous) { $Previous[$key] = $statement }
                    $replace = $true; break
                }
            }
            if (-not $replace) { [void]$result.Append($statement) }
            $start = $i + 1
        }
        $i++
    }
    if ($i -ge $Text.Length -and $start -lt $Text.Length) {
        if ($quote -or $depth -ne 0) { throw 'invalid_config' }
        return Set-RootConfig ($Text + "`n") $Settings $Previous
    }
    foreach ($key in ($Settings.Keys | Sort-Object)) { [void]$result.Append($key + ' = ' + $Settings[$key] + "`n") }
    [void]$result.Append($Text.Substring($start))
    return $result.ToString()
}

function Get-CodexExecutable {
    foreach ($packageName in @('OpenAI.Codex', 'OpenAI.ChatGPT-Desktop', 'OpenAI.ChatGPT')) {
        foreach ($pkg in @(Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue)) {
            foreach ($relative in @('app\ChatGPT.exe', 'app\Codex.exe', 'ChatGPT.exe')) {
                $candidate = Join-Path $pkg.InstallLocation $relative
                if ([IO.File]::Exists($candidate)) { return $candidate }
            }
        }
    }
    foreach ($relative in @('OpenAI\Codex\ChatGPT.exe', 'OpenAI\Codex\Codex.exe', 'Programs\Codex\Codex.exe')) {
        $candidate = Join-Path $env:LOCALAPPDATA $relative
        if ([IO.File]::Exists($candidate)) { return $candidate }
    }
    return ''
}
function Get-CodexProcesses {
    $exe = Get-CodexExecutable
    if (-not $exe) { return @() }
    $items = @(Get-CimInstance Win32_Process)
    $ids = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($item in $items) {
        if ([string]::Equals([string]$item.ExecutablePath, $exe, [StringComparison]::OrdinalIgnoreCase)) { [void]$ids.Add([int]$item.ProcessId) }
    }
    do {
        $added = $false
        foreach ($item in $items) {
            if ($ids.Contains([int]$item.ParentProcessId) -and $ids.Add([int]$item.ProcessId)) { $added = $true }
        }
    } while ($added)
    return @($items | Where-Object { $ids.Contains([int]$_.ProcessId) })
}
function Stop-Codex {
    $items = @(Get-CodexProcesses)
    foreach ($item in $items) {
        $process = Get-Process -Id $item.ProcessId -ErrorAction SilentlyContinue
        if ($process -and $process.MainWindowHandle -ne 0) { [void]$process.CloseMainWindow() }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(2)
    do {
        $remaining = @($items | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
        if ($remaining.Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    foreach ($item in $remaining) {
        $process = Get-Process -Id $item.ProcessId -ErrorAction SilentlyContinue
        if ($process) { $process.Kill(); if (-not $process.WaitForExit(3000)) { throw 'stop_failed' } }
    }
    if (@(Get-CodexProcesses).Count -gt 0) { throw 'stop_failed' }
}
function Start-Codex {
    $exe = Get-CodexExecutable
    if (-not $exe) { throw 'not_installed' }
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $exe
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.EnvironmentVariables['CODEX_HOME'] = Get-ActiveHome
    $startInfo.EnvironmentVariables.Remove('CODEX_ELECTRON_USER_DATA_PATH')
    $startInfo.EnvironmentVariables.Remove('ELECTRON_RUN_AS_NODE')
    $process = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) { throw 'launch_failed' }
    Start-Sleep -Milliseconds 900
    if (@(Get-CodexProcesses).Count -eq 0) { throw 'launch_failed' }
}

function Convert-Usage($Payload) {
    $usage = @{ five_hour = -1; weekly = -1; five_hour_reset = 0; weekly_reset = 0; plan = [string]$Payload.plan_type; updated_at = [DateTime]::UtcNow.ToString('o') }
    foreach ($window in @($Payload.rate_limit.primary_window, $Payload.rate_limit.secondary_window)) {
        if ($null -eq $window -or $null -eq $window.used_percent) { continue }
        $percent = 0.0
        if (-not [double]::TryParse([string]$window.used_percent, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$percent) -or [double]::IsNaN($percent) -or [double]::IsInfinity($percent)) { continue }
        $key = switch ([int]$window.limit_window_seconds) { 18000 { 'five_hour' } 604800 { 'weekly' } default { '' } }
        if ($key) {
            $usage[$key] = [Math]::Max(0, [Math]::Min(100, 100 - $percent))
            $usage[$key + '_reset'] = [long]$window.reset_at
        }
    }
    return $usage
}
function Get-Usage($Path) {
    $auth = Update-AccountTokens $Path
    $info = Get-AuthInfo $auth
    if ($info.auth_kind -eq 'api') { throw 'api_usage_unsupported' }
    if (-not $info.account_id) { throw 'missing_account_id' }
    $headers = @{ Authorization = 'Bearer ' + $auth.tokens.access_token; 'ChatGPT-Account-Id' = $info.account_id; Accept = 'application/json' }
    try {
        # Fixed official origin: imported credentials never choose a destination.
        $payload = Invoke-RestMethod -Uri 'https://chatgpt.com/backend-api/wham/usage' -Headers $headers -UserAgent 'HexagonProxy' -TimeoutSec 18 -MaximumRedirection 0
    } catch {
        $status = 0
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        if ($status -eq 401) {
            $auth = Update-AccountTokens $Path $true
            $headers.Authorization = 'Bearer ' + $auth.tokens.access_token
            try { $payload = Invoke-RestMethod -Uri 'https://chatgpt.com/backend-api/wham/usage' -Headers $headers -UserAgent 'HexagonProxy' -TimeoutSec 18 -MaximumRedirection 0 }
            catch { throw 'usage_failed' }
        }
        elseif ($status -eq 403) { throw 'usage_forbidden' }
        elseif ($status -eq 429) { throw 'usage_rate_limited' }
        else { throw 'usage_failed' }
    }
    if ($null -eq $payload.rate_limit) { throw 'usage_invalid' }
    return @{ ok = $true; usage = (Convert-Usage $payload); account = $info }
}

function Get-RecoveryInfo {
    $path = Join-Path (Get-ActiveHome) '.hexagonproxy-recovery.json'
    if (-not [IO.File]::Exists($path)) { return @{ required = $false } }
    $journal = Read-JsonFile $path
    if ($journal.index_path -and $journal.index_hash -and [IO.File]::Exists($journal.index_path)) {
        if ((Get-FileHash -LiteralPath $journal.index_path -Algorithm SHA256).Hash -eq $journal.index_hash) {
            return @{ required = $false }
        }
    }
    return @{ required = $true; snapshot = [string]$journal.snapshot; was_running = [bool]$journal.was_running }
}

function Clear-Recovery {
    $path = Join-Path (Get-ActiveHome) '.hexagonproxy-recovery.json'
    if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
}

function Invoke-Switch {
    $live = Get-ActiveHome
    if ((Get-RecoveryInfo).required) { throw 'recovery_required' }
    if (-not (Get-CodexExecutable)) { throw 'not_installed' }
    # An auth.json pointer is not a backup of OS keyring credentials. Refuse to
    # replace such a login rather than presenting an unusable return account.
    $liveConfigPath = Join-Path $live 'config.toml'
    if ([IO.File]::Exists($liveConfigPath)) {
        $previousSettings = @{}
        $null = Set-RootConfig ([IO.File]::ReadAllText($liveConfigPath)) @{ cli_auth_credentials_store = '"file"' } $previousSettings
        if ([string]$previousSettings.cli_auth_credentials_store -match '=\s*[\x22\x27](keyring|auto)[\x22\x27]') { throw 'current_auth_unavailable' }
    }
    if ([IO.File]::Exists((Join-Path $live 'auth.json')) -and -not (Get-HomeInfo $live).login_present) { throw 'current_auth_unavailable' }
    Assert-DifferentDirectories $live $CodexHome
    Assert-DifferentDirectories $live $CurrentSnapshot
    Assert-Snapshot $CodexHome
    # Validate the target before stopping the application or writing active files.
    $authPath = Join-Path $CodexHome 'auth.json'
    $newAuth = $null
    if ([IO.File]::Exists($authPath)) { $null = Update-AccountTokens $CodexHome; $newAuth = [IO.File]::ReadAllBytes($authPath); $null = Get-AuthInfo (Read-JsonFile $authPath) }
    elseif (-not [IO.File]::Exists((Join-Path $CodexHome 'snapshot.json'))) { throw 'snapshot_missing' }
    $configPath = Join-Path $CodexHome 'config.toml'
    $newConfig = $null
    $configText = ''
    if ([IO.File]::Exists($configPath)) { $configText = [IO.File]::ReadAllText($configPath) }
    # Ensure the selected file credentials take effect even if the source used keyring.
    $newConfig = $script:Utf8.GetBytes((Set-RootConfig $configText @{ cli_auth_credentials_store = '"file"' }))
    $pending = $PendingIndex
    if (-not $pending) { $pending = $IndexPath + '.pending' }
    $nextIndex = $null
    if ($IndexPath) {
        if (-not [IO.File]::Exists($pending)) { throw 'index_failed' }
        $nextIndex = [IO.File]::ReadAllBytes($pending)
        if ($ExpectedProfileId -and [IO.File]::Exists($IndexPath) -and (Read-JsonFile $IndexPath).selected_id -ne $ExpectedProfileId) { throw 'state_changed' }
    }
    $wasRunning = @(Get-CodexProcesses).Count -gt 0
    Stop-Codex
    # Shutdown first, then capture the latest token refreshed by the app.
    $rollbackSnapshot = Join-Path $live ('.hexagonproxy-rollback-' + [guid]::NewGuid().ToString('N'))
    try {
        Save-Snapshot $live $rollbackSnapshot
        Sync-AccountState $live $CurrentSnapshot
    }
    catch {
        if ($wasRunning) { try { Start-Codex } catch {} }
        throw 'backup_failed'
    }
    try {
        $journal = @{ snapshot = $rollbackSnapshot; was_running = $wasRunning; index_path = $IndexPath }
        if ($IndexPath) { $journal.index_hash = (Get-FileHash -LiteralPath $pending -Algorithm SHA256).Hash }
        Write-JsonFile (Join-Path $live '.hexagonproxy-recovery.json') $journal
        foreach ($entry in @(@{ name = 'auth.json'; bytes = $newAuth }, @{ name = 'config.toml'; bytes = $newConfig })) {
            $target = Join-Path $live $entry.name
            if ($null -ne $entry.bytes) { Write-Atomic $target $entry.bytes }
            elseif ([IO.File]::Exists($target)) { [IO.File]::Delete($target) }
        }
        Start-Codex
        if ($IndexPath) { Write-Atomic $IndexPath $nextIndex }
    } catch {
        try {
            Stop-Codex
            Restore-Snapshot $rollbackSnapshot $live
            Clear-Recovery
        } catch { return @{ ok = $false; message_code = 'rollback_failed'; recovery_path = $rollbackSnapshot } }
        $restarted = $false
        if ($wasRunning) { try { Start-Codex; $restarted = $true } catch {} }
        return @{ ok = $false; message_code = 'switch_rolled_back'; running = $restarted }
    }
    # Index commit is the transaction boundary. A leftover marker after a cleanup
    # failure is recognized as committed on the next inspection.
    try { Clear-Recovery } catch {}
    return @{ ok = $true; running = $true; message_code = 'switched' }
}

function Invoke-Action {
    $live = Get-ActiveHome
    $recovery = Get-RecoveryInfo
    if ($recovery.required -and $Action -notin @('inspect', 'usage', 'recover')) { throw 'recovery_required' }
    switch ($Action) {
        'login' { return Invoke-Login }
        'inspect' { return @{ ok = $true; installed = [bool](Get-CodexExecutable); running = (@(Get-CodexProcesses).Count -gt 0); active_home = $live; account = (Get-HomeInfo $live); recovery_required = $recovery.required } }
        'recover' {
            if (-not $recovery.required) { return @{ ok = $true } }
            Assert-Snapshot $recovery.snapshot
            Stop-Codex
            Restore-Snapshot $recovery.snapshot $live
            Clear-Recovery
            $restarted = $false
            if ($recovery.was_running) { try { Start-Codex; $restarted = $true } catch {} }
            return @{ ok = $true; running = $restarted }
        }
        'launch' {
            if (@(Get-CodexProcesses).Count -eq 0) { Start-Codex }
            return @{ ok = $true; running = $true; message_code = 'launched' }
        }
        'capture' {
            $info = Get-HomeInfo $live
            if (-not $info.login_present) { throw 'missing_tokens' }
            Save-Snapshot $live $CodexHome
            Publish-AccountCredentials $CodexHome
            return @{ ok = $true; account = $info; message_code = 'captured' }
        }
        { $_ -in @('import', 'prepare') } {
            $auth = $null
            $info = @{ login_present = $false }
            if ($Action -eq 'import') {
                if ((Get-Item -LiteralPath $ImportPath).Length -gt 4MB) { throw 'invalid_auth' }
                $auth = Read-JsonFile $ImportPath
                $info = Get-AuthInfo $auth
            }
            $config = ''
            $configPath = Join-Path $live 'config.toml'
            if ([IO.File]::Exists($configPath)) { $config = [IO.File]::ReadAllText($configPath) }
            $loginMethod = if ($info.auth_kind -eq 'api') { '"api"' } else { '"chatgpt"' }
            $config = Set-RootConfig $config @{ model_provider = '"openai"'; cli_auth_credentials_store = '"file"'; forced_login_method = $loginMethod }
            Assert-DifferentDirectories $live $CodexHome
            if ($null -ne $auth) { Write-JsonFile (Join-Path $CodexHome 'auth.json') $auth }
            Write-Atomic (Join-Path $CodexHome 'config.toml') $script:Utf8.GetBytes($config)
            Write-SnapshotManifest $CodexHome
            return @{ ok = $true; account = $info; message_code = 'imported' }
        }
        'usage' { return Get-Usage $CodexHome }
        'switch' { return Invoke-Switch }
    }
}

if (-not $Library) {
    $lock = $null
    try {
        if ($Action -ne 'inspect') {
            $live = Get-ActiveHome
            [void][IO.Directory]::CreateDirectory($live)
            try { $lock = [IO.File]::Open((Join-Path $live '.hexagonproxy.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
            catch { throw 'busy' }
        }
        $result = Invoke-Action
    } catch {
        # Exception bodies can contain credentials, so only return stable codes.
        $known = @('unsafe_path', 'snapshot_missing', 'invalid_auth', 'missing_tokens', 'invalid_config', 'not_installed', 'stop_failed', 'backup_failed', 'launch_failed', 'index_failed', 'api_usage_unsupported', 'missing_account_id', 'login_expired', 'usage_forbidden', 'usage_rate_limited', 'usage_failed', 'usage_invalid', 'busy', 'recovery_required', 'state_changed', 'current_auth_unavailable')
        $known += @('auth_refresh_pending', 'reauthorization_required', 'token_refresh_failed', 'cli_missing', 'login_timeout', 'login_failed', 'browser_failed')
        $code = 'operation_failed'
        if ($known -contains $_.Exception.Message) { $code = $_.Exception.Message }
        $result = @{ ok = $false; message_code = $code; error_type = $_.Exception.GetType().Name; error_line = $_.InvocationInfo.ScriptLineNumber }
    } finally { if ($lock) { $lock.Dispose() } }
    if ($ResultPath) { Write-JsonFile $ResultPath $result }
    else { $result | ConvertTo-Json -Compress -Depth 12 }
    exit 0
}
