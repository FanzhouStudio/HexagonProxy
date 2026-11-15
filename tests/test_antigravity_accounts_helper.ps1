$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../scripts/windows_antigravity_accounts_helper.ps1') -Library
$Root = Join-Path $PSScriptRoot '../temp_appdata/account-helper-fixture'
$ExePath = 'C:\fixture\Antigravity.exe'
$AccountId = '0123456789abcdef0123456789abcdef'
$originalUser = $env:USERPROFILE
$path = Get-ProfilePath
$info = Get-LaunchInfo $path
if ($info.UseShellExecute -or -not $info.Arguments.Contains('--user-data-dir="') -or -not $info.EnvironmentVariables['USERPROFILE'].StartsWith([IO.Path]::GetFullPath($Root))) { throw 'Profile isolation failed' }
if ($env:USERPROFILE -ne $originalUser) { throw 'Parent environment modified' }
$editor = @{Name='Antigravity.exe';CommandLine=('"C:\fixture\Antigravity.exe" --user-data-dir="' + (Join-Path $path 'data').Replace('\','/') + '"')}
if (-not (Test-ProfileEditor $editor $path)) { throw 'Forward slash profile matching failed' }
$editor.CommandLine += ' --type=renderer'
if (Test-ProfileEditor $editor $path) { throw 'Renderer cannot identify an account' }
$editor.CommandLine = '"C:\fixture\Antigravity.exe" --user-data-dir="C:\other\data"'
if (Test-ProfileEditor $editor $path) { throw 'Another account matched' }
$AccountId = '../escape'
try { Get-ProfilePath; throw 'Accepted traversal' } catch { if ($_.Exception.Message -eq 'Accepted traversal') { throw } }
$AccountId = 'default'
$default = Get-LaunchInfo (Get-ProfilePath)
if ($default.Arguments) { throw 'Default profile must use original data' }
$sample = @{ userStatus = @{ email = 'fixture@example.com'; cascadeModelConfigData = @{ clientModelConfigs = @(
    @{ label = 'Model A'; quotaInfo = @{remainingFraction = 0; resetTime = '2030-01-01T00:00:00Z'} },
    @{ label = 'Model B'; quotaInfo = @{remainingFraction = 0.75} },
    @{ label = 'Unknown'; quotaInfo = @{} },
    @{ label = 'Invalid'; quotaInfo = @{remainingFraction = 2} }
) } } }
$quota = Convert-Quota $sample
if ($quota.models.Count -ne 2 -or $quota.models[0].remaining -ne 0 -or $quota.models[1].remaining -ne 75) { throw 'Quota normalization failed' }
try { Convert-Quota @{userStatus=@{}}; throw 'Empty quota accepted' } catch { if ($_.Exception.Message -eq 'Empty quota accepted') { throw } }
function Get-CimInstance { return @() }
$missing = Read-Quota $path
if ($missing.ok -or $missing.discovery -ne 'profile_not_running' -or $missing.editor_running) { throw 'Missing editor must not be confused with a logged-out account' }
$AccountId = '0123456789abcdef0123456789abcdef'
$editor = @{Name='Antigravity.exe';ProcessId=10;ParentProcessId=1;CommandLine=('"C:\fixture\Antigravity.exe" --user-data-dir="' + (Join-Path $path 'data') + '"')}
$otherEditor = @{Name='Antigravity.exe';ProcessId=20;ParentProcessId=1;CommandLine='"C:\fixture\Antigravity.exe"'}
$failure = Get-QuotaDiscoveryFailure @($otherEditor) $path 0 0
if ($failure.discovery -ne 'profile_not_running') { throw 'Default window cannot stand in for another account' }
$failure = Get-QuotaDiscoveryFailure @($editor) $path 0 0
if ($failure.discovery -ne 'server_not_started' -or -not $failure.editor_running) { throw 'Missing server must report selected window state' }
$unreadableEditor = @{Name='Antigravity.exe';CommandLine=$null}
$failure = Get-QuotaDiscoveryFailure @($otherEditor,$unreadableEditor) $path 0 0
if ($failure.discovery -ne 'process_access_denied' -or $failure.ContainsKey('editor_running')) { throw 'Unreadable editor cannot be classified as stopped' }
$failure = Get-QuotaDiscoveryFailure @($editor) $path 1 0
if ($failure.discovery -ne 'unsupported_arguments') { throw 'Unknown interface arguments must be distinguished from missing server' }
if ($null -ne (Get-QuotaDiscoveryFailure @($editor) $path 1 1)) { throw 'Valid selected server rejected' }
Write-Output 'PASS: isolated child launch environment, default profile, traversal rejection and quota parsing'
