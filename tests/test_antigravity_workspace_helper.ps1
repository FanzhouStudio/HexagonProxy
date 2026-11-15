$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../scripts/windows_antigravity_workspace_helper.ps1')
$fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('../temp_appdata/workspace-sharing-' + [guid]::NewGuid().ToString('N'))))
$original = Join-Path $fixture 'original-home'
$profile = Join-Path $fixture 'accounts/account-one'
$second = Join-Path $fixture 'accounts/account-two'
$common = Join-Path $original '.gemini/antigravity'
$private = Join-Path $profile 'home/.gemini/antigravity'
foreach ($directory in @((Join-Path $common 'conversations'),(Join-Path $private 'conversations'),(Join-Path $original '.gemini/config/projects'),(Join-Path $profile 'home/.gemini/config/projects'))) { [void][IO.Directory]::CreateDirectory($directory) }
[IO.File]::WriteAllText((Join-Path $common 'conversations/original.db'),'original transcript')
[IO.File]::WriteAllText((Join-Path $private 'conversations/added.db'),'account transcript')
[IO.File]::WriteAllText((Join-Path $private 'conversations/original.db'),'different collision retained in backup')
[IO.File]::WriteAllText((Join-Path $original '.gemini/config/projects/original.json'),'original project')
[IO.File]::WriteAllText((Join-Path $profile 'home/.gemini/config/projects/added.json'),'added project')
$token = Join-Path $profile 'home/.gemini/jetski-standalone-oauth-token'
[IO.File]::WriteAllText($token,'fixture credential stays private')
Initialize-WorkspaceSqlite
$schema = 'CREATE TABLE conversation_summaries (conversation_id TEXT PRIMARY KEY,title TEXT); CREATE TABLE conversation_parents(conversation_id TEXT PRIMARY KEY,parent_id TEXT);'
$targetDb = Join-Path $common 'conversation_summaries.db'
$sourceDb = Join-Path $private 'conversation_summaries.db'
[void][HexagonWorkspaceSqlite]::Exec($targetDb,($schema + "INSERT INTO conversation_summaries VALUES('original','original title');"))
[void][HexagonWorkspaceSqlite]::Exec($sourceDb,($schema + "INSERT INTO conversation_summaries VALUES('original','must not overwrite'); INSERT INTO conversation_summaries VALUES('added','added title');"))
Initialize-SharedWorkspace $profile $original
if (-not (Test-SharedWorkspace $profile $original)) { throw 'Shared junctions not prepared' }
if ([IO.File]::ReadAllText($token) -ne 'fixture credential stays private') { throw 'Credential was modified' }
if (-not [IO.File]::Exists((Join-Path $common 'conversations/added.db')) -or [IO.File]::ReadAllText((Join-Path $common 'conversations/original.db')) -ne 'original transcript') { throw 'Conversation data merge failed or replaced an original' }
$rows = [HexagonWorkspaceSqlite]::Exec($targetDb,'SELECT conversation_id,title FROM conversation_summaries ORDER BY conversation_id;')
if ($rows.Length -ne 2 -or $rows[1][1] -ne 'original title') { throw 'Transactional conversation index merge failed' }
if (@(Get-ChildItem -LiteralPath (Join-Path $profile 'home/.gemini') -Directory | Where-Object { $_.Name -like '*.before-sharing-*' }).Count -ne 2) { throw 'Original directories not backed up' }
Initialize-SharedWorkspace $profile $original
Initialize-SharedWorkspace $second $original
if (-not [IO.File]::Exists((Join-Path $second 'home/.gemini/antigravity/conversations/original.db')) -or -not [IO.File]::Exists((Join-Path $second 'home/.gemini/config/projects/added.json'))) { throw 'Switching another account loses prior conversations or projects' }
if ([IO.File]::Exists((Join-Path $second 'home/.gemini/jetski-standalone-oauth-token'))) { throw 'Credential leaked to another account' }
$sourceData = Join-Path $fixture 'source-ui'
$targetData = Join-Path $fixture 'target-ui'
[void][IO.Directory]::CreateDirectory($sourceData); [void][IO.Directory]::CreateDirectory($targetData)
[IO.File]::WriteAllText((Join-Path $sourceData 'app_storage.json'),'{"projectsOrder":["project"],"lastCreatedProjectId":"project","agy.onboarding.lastLoginUsername":"another-account"}')
[IO.File]::WriteAllText((Join-Path $targetData 'app_storage.json'),'{"agy.onboarding.lastLoginUsername":"target-account"}')
Copy-WorkspaceUi $sourceData $targetData
$ui = [IO.File]::ReadAllText((Join-Path $targetData 'app_storage.json')) | ConvertFrom-Json
if ($ui.lastCreatedProjectId -ne 'project' -or $ui.'agy.onboarding.lastLoginUsername' -ne 'target-account') { throw 'Workspace UI transfer changed login identity' }
$broken = Join-Path $fixture 'broken-profile'
$brokenHistory = Join-Path $broken 'home/.gemini/antigravity'
[void][IO.Directory]::CreateDirectory($brokenHistory)
[IO.File]::WriteAllText((Join-Path $brokenHistory 'conversation_summaries.db'),'not a sqlite database')
$failed = $false
try { Initialize-SharedWorkspace $broken $original } catch { $failed = $true }
if (-not $failed -or -not [IO.File]::Exists((Join-Path $brokenHistory 'conversation_summaries.db')) -or (Get-Item -LiteralPath $brokenHistory).LinkType) { throw 'Failed migration must restore the original private directory' }
$interrupted = Join-Path $fixture 'interrupted'
$history = Join-Path $interrupted 'home/.gemini/antigravity'
$restoreBackup = $history + '.before-sharing-test'
[void][IO.Directory]::CreateDirectory((Join-Path $restoreBackup 'conversations'))
[IO.File]::WriteAllText((Join-Path $restoreBackup 'conversations/recovered.db'),'interrupted history')
[IO.File]::WriteAllText(($history + '.sharing.json'),(@{backup=$restoreBackup;target=$common}|ConvertTo-Json))
Initialize-SharedWorkspace $interrupted $original
if (-not [IO.File]::Exists((Join-Path $common 'conversations/recovered.db')) -or -not (Test-SharedWorkspace $interrupted $original)) { throw 'Interrupted migration recovery failed' }
Write-Output 'PASS: shared projects/history, SQLite merge, idempotence, private credentials, backups and workspace UI without auth crossover'
