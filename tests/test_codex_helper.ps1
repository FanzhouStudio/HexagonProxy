$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\windows_codex_profile_helper.ps1') -Library
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('hexagon-codex-tests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$script:checks = 0
function Assert($Condition, $Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:checks++
}
function Write-Text($Path, $Text) { Write-Atomic $Path $script:Utf8.GetBytes($Text) }
function Fake-Auth($Label) { return @{ tokens = @{ access_token = "test-access-$Label"; id_token = "test-id-$Label"; refresh_token = "test-refresh-$Label"; account_id = "test-account-$Label" } } }
function New-Fixture($Name) {
    $script:ActiveHome = Join-Path $testRoot ($Name + '\active')
    $script:CodexHome = Join-Path $testRoot ($Name + '\target')
    $script:CurrentSnapshot = Join-Path $testRoot ($Name + '\current')
    $script:IndexPath = Join-Path $testRoot ($Name + '\index.json')
    Write-JsonFile (Join-Path $ActiveHome 'auth.json') (Fake-Auth 'old')
    Write-Text (Join-Path $ActiveHome 'config.toml') "model_provider = 'relay'"
    Write-Text (Join-Path $ActiveHome 'sessions\history.jsonl') 'untouched history'
    Write-Text (Join-Path $ActiveHome 'state_5.sqlite') 'untouched database'
    Write-JsonFile (Join-Path $CodexHome 'auth.json') (Fake-Auth 'new')
    Write-Text (Join-Path $CodexHome 'config.toml') "model_provider = 'openai'"
    Write-SnapshotManifest $CodexHome
    Write-Text $IndexPath '{"selected_id":"old"}'
    Write-Text ($IndexPath + '.pending') '{"selected_id":"new"}'
    $script:fakeRunning = $true
    $script:events = @()
    $script:launchCalls = 0
    $script:failLaunch = $false
}
# Never stop/start a real desktop process.
function Get-CodexExecutable { return 'test-only.exe' }
function Get-CodexProcesses { if ($script:fakeRunning) { return @(@{ ProcessId = 1 }) }; return @() }
function Stop-Codex { $script:events += 'stop'; $script:fakeRunning = $false }
function Start-Codex {
    $script:events += 'start'; $script:launchCalls++
    if ($script:failLaunch -and $script:launchCalls -eq 1) { throw 'launch_failed' }
    $script:fakeRunning = $true
}

New-Fixture 'success'
$result = Invoke-Switch
Assert $result.ok 'switch succeeds'
Assert ((Read-JsonFile (Join-Path $ActiveHome 'auth.json')).tokens.account_id -eq 'test-account-new') 'target activated'
Assert ((Read-JsonFile (Join-Path $CurrentSnapshot 'auth.json')).tokens.account_id -eq 'test-account-old') 'outgoing auth preserved'
Assert ((Read-JsonFile $IndexPath).selected_id -eq 'new') 'selection committed'
Assert ([IO.File]::ReadAllText((Join-Path $ActiveHome 'sessions\history.jsonl')) -eq 'untouched history') 'history retained'
Assert ([IO.File]::ReadAllText((Join-Path $ActiveHome 'state_5.sqlite')) -eq 'untouched database') 'database retained'
Assert (-not [IO.Directory]::Exists((Join-Path $CurrentSnapshot 'sessions'))) 'history excluded from snapshot'
Assert (([IO.File]::ReadAllText((Join-Path $ActiveHome 'config.toml'))) -match 'cli_auth_credentials_store = "file"') 'file credentials selected'
Assert (($script:events -join ',') -eq 'stop,start') 'shutdown precedes launch'

New-Fixture 'launch-failure'
$script:failLaunch = $true
$beforeAuth = [IO.File]::ReadAllText((Join-Path $ActiveHome 'auth.json'))
$beforeConfig = [IO.File]::ReadAllText((Join-Path $ActiveHome 'config.toml'))
$result = Invoke-Switch
Assert (-not $result.ok -and $result.message_code -eq 'switch_rolled_back') 'launch failure reported'
Assert ([IO.File]::ReadAllText((Join-Path $ActiveHome 'auth.json')) -eq $beforeAuth) 'auth rollback exact'
Assert ([IO.File]::ReadAllText((Join-Path $ActiveHome 'config.toml')) -eq $beforeConfig) 'config rollback exact'
Assert ((Read-JsonFile $IndexPath).selected_id -eq 'old') 'selection unchanged after failure'
Assert $result.running 'previous desktop restarted'

New-Fixture 'partial-write'
$script:originalAtomic = (Get-Item Function:\Write-Atomic).ScriptBlock
$script:writeFailure = $false
function Write-Atomic([string]$Path, [byte[]]$Bytes) {
    if (-not $script:writeFailure -and $Path -eq (Join-Path $ActiveHome 'config.toml')) {
        $script:writeFailure = $true; throw 'simulated disk failure'
    }
    & $script:originalAtomic $Path $Bytes
}
$result = Invoke-Switch
Assert (-not $result.ok) 'partial write rejected'
Assert ((Read-JsonFile (Join-Path $ActiveHome 'auth.json')).tokens.account_id -eq 'test-account-old') 'partial auth write rolled back'
Assert ([IO.File]::ReadAllText((Join-Path $ActiveHome 'config.toml')) -eq "model_provider = 'relay'") 'partial config write rolled back'
Set-Item -LiteralPath Function:\Write-Atomic -Value $script:originalAtomic

New-Fixture 'index-failure'
$script:writeFailure = $false
function Write-Atomic([string]$Path, [byte[]]$Bytes) {
    if (-not $script:writeFailure -and $Path -eq $IndexPath) { $script:writeFailure = $true; throw 'simulated index failure' }
    & $script:originalAtomic $Path $Bytes
}
$result = Invoke-Switch
Assert (-not $result.ok) 'index commit failure rejected'
Assert ((Read-JsonFile (Join-Path $ActiveHome 'auth.json')).tokens.account_id -eq 'test-account-old') 'index failure rolls auth back'
Assert ((Read-JsonFile $IndexPath).selected_id -eq 'old') 'index failure keeps old selection'
Set-Item -LiteralPath Function:\Write-Atomic -Value $script:originalAtomic

New-Fixture 'invalid-target'
Write-Text (Join-Path $CodexHome 'auth.json') '{bad'
$threw = $false
try { $null = Invoke-Switch } catch { $threw = $true }
Assert $threw 'invalid target rejected'
Assert ($script:events.Count -eq 0) 'invalid target rejected before stopping'

New-Fixture 'deleted-token'
[IO.File]::Delete((Join-Path $CodexHome 'auth.json'))
$threw = $false
try { $null = Invoke-Switch } catch { $threw = $true }
Assert $threw 'missing token does not become blank login'

New-Fixture 'new-login'
[IO.File]::Delete((Join-Path $CodexHome 'auth.json'))
Write-SnapshotManifest $CodexHome
$result = Invoke-Switch
Assert $result.ok 'intentional blank profile accepted'
Assert (-not [IO.File]::Exists((Join-Path $ActiveHome 'auth.json'))) 'new profile does not inherit previous token'

$config = @"
# shared settings
model_provider = 'relay'
"cli_auth_credentials_store" = 'auto'
instructions = """
[not_a_table]
model_provider = 'inside-string'
"""
projects = [
 "a",
 "b"
]
[model_providers.relay]
base_url = "https://example.invalid/v1"
[mcp_servers.demo]
command = "my-server"
"@
$changed = Set-RootConfig $config @{ model_provider = '"openai"'; cli_auth_credentials_store = '"file"' }
Assert ($changed.Contains("model_provider = 'inside-string'")) 'multiline string unchanged'
Assert ($changed.Contains('[mcp_servers.demo]')) 'MCP settings retained'
Assert ($changed.Contains('base_url = "https://example.invalid/v1"')) 'provider definition retained'
Assert (-not $changed.Contains("model_provider = 'relay'")) 'root provider replaced'
Assert (([regex]::Matches($changed, 'cli_auth_credentials_store')).Count -eq 1) 'quoted root key not duplicated'
Assert ((Set-RootConfig "model_provider = 'relay'" @{ model_provider = '"openai"' }) -eq ('model_provider = "openai"' + [char]10)) 'no final newline supported'
$nestedConfig = '[model_providers.demo]' + [char]10 + "model_provider = 'nested'"
Assert ((Set-RootConfig $nestedConfig @{ model_provider = '"openai"' }).EndsWith($nestedConfig)) 'nested keys unchanged'
Write-Text (Join-Path $testRoot 'edited.toml') $changed

$payload = @{ plan_type = 'plus'; rate_limit = @{
    primary_window = @{ used_percent = 25; limit_window_seconds = 604800; reset_at = 1900000000 }
    secondary_window = @{ used_percent = 0; limit_window_seconds = 18000; reset_at = 1800000000 }
} }
$usage = Convert-Usage $payload
Assert ($usage.five_hour -eq 100 -and $usage.weekly -eq 75) 'remaining mapped by duration'
$payload.rate_limit.primary_window.used_percent = $null
$payload.rate_limit.secondary_window.used_percent = 130
$usage = Convert-Usage $payload
Assert ($usage.weekly -eq -1 -and $usage.five_hour -eq 0) 'unknown preserved and percent clamped'
$payload.rate_limit.secondary_window.used_percent = 'not-a-number'
Assert ((Convert-Usage $payload).five_hour -eq -1) 'malformed percent unknown'
$payload.rate_limit.secondary_window.used_percent = 'NaN'
Assert ((Convert-Usage $payload).five_hour -eq -1) 'NaN unknown'

# Exercise the real entry point with fake auth and temporary storage.
$importRoot = Join-Path $testRoot 'import'
$fakePath = Join-Path $importRoot 'input.json'
Write-JsonFile $fakePath (Fake-Auth 'import')
$scriptPath = Join-Path $PSScriptRoot '..\scripts\windows_codex_profile_helper.ps1'
$json = & powershell.exe -NoLogo -NoProfile -NonInteractive -File $scriptPath -Action import -ActiveHome (Join-Path $importRoot 'active') -CodexHome (Join-Path $importRoot 'snapshot') -ImportPath $fakePath
Assert ($json | ConvertFrom-Json).ok 'helper import succeeds'
Assert (-not ($json -match 'test-access|test-refresh')) 'response contains no tokens'
Assert (-not [IO.File]::Exists((Join-Path $importRoot 'active\auth.json'))) 'import does not activate credentials'
Assert-Snapshot (Join-Path $importRoot 'snapshot')
Write-Text $fakePath '{"tokens": {}}'
$json = & powershell.exe -NoLogo -NoProfile -NonInteractive -File $scriptPath -Action import -ActiveHome (Join-Path $importRoot 'active') -CodexHome (Join-Path $importRoot 'invalid') -ImportPath $fakePath
Assert (-not ($json | ConvertFrom-Json).ok) 'incomplete auth rejected'
New-Fixture 'interrupted'
Save-Snapshot $ActiveHome $CurrentSnapshot
Write-JsonFile (Join-Path $ActiveHome '.hexagonproxy-recovery.json') @{ snapshot = $CurrentSnapshot; was_running = $true }
Write-JsonFile (Join-Path $ActiveHome 'auth.json') (Fake-Auth 'partial')
Assert (Get-RecoveryInfo).required 'interrupted transaction detected'
$threw = $false
try { $null = Invoke-Switch } catch { $threw = $_.Exception.Message -eq 'recovery_required' }
Assert $threw 'unrecovered transaction blocks another switch'
$script:Action = 'recover'
$recovered = Invoke-Action
Assert $recovered.ok 'interrupted switch restored'
Assert ((Read-JsonFile (Join-Path $ActiveHome 'auth.json')).tokens.account_id -eq 'test-account-old') 'recovery restores original authentication'
Assert (-not (Get-RecoveryInfo).required) 'recovery marker cleared'

New-Fixture 'committed-marker'
Write-JsonFile (Join-Path $ActiveHome '.hexagonproxy-recovery.json') @{ snapshot = $CurrentSnapshot; index_path = $IndexPath; index_hash = (Get-FileHash -LiteralPath $IndexPath).Hash }
Assert (-not (Get-RecoveryInfo).required) 'committed index prevents accidental rollback'

New-Fixture 'stale-instance'
$script:ExpectedProfileId = 'stale-id'
$threw = $false
try { $null = Invoke-Switch } catch { $threw = $_.Exception.Message -eq 'state_changed' }
Assert $threw 'stale instance cannot overwrite current account snapshot'
Assert ($script:events.Count -eq 0) 'stale selection detected before shutdown'
$script:ExpectedProfileId = ''

New-Fixture 'keyring'
Write-Text (Join-Path $ActiveHome 'config.toml') 'cli_auth_credentials_store = "keyring"'
$threw = $false
try { $null = Invoke-Switch } catch { $threw = $_.Exception.Message -eq 'current_auth_unavailable' }
Assert $threw 'non-file login cannot be replaced without a reliable backup'
Assert ($script:events.Count -eq 0) 'keyring check runs before stopping app'

New-Fixture 'usage'
function Invoke-RestMethod($Uri, $Headers, $UserAgent, $TimeoutSec, $MaximumRedirection) {
    Assert ($Uri -eq 'https://chatgpt.com/backend-api/wham/usage') 'usage only uses fixed official origin'
    Assert ($MaximumRedirection -eq 0) 'credentials cannot follow a redirect'
    return @{ plan_type = 'plus'; rate_limit = @{ primary_window = @{ used_percent = 20; limit_window_seconds = 18000; reset_at = 1900000000 } } }
}
$fetched = Get-Usage $ActiveHome
Assert ($fetched.ok -and $fetched.usage.five_hour -eq 80) 'usage HTTP payload mapped'
function Invoke-RestMethod { throw 'test-access-private-must-not-escape' }
$errorCode = ''
try { $null = Get-Usage $ActiveHome } catch { $errorCode = $_.Exception.Message }
Assert ($errorCode -eq 'usage_failed') 'network error body redacted'
Write-Output "PASS: $script:checks Codex helper checks; fixtures: $testRoot"
