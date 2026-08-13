$ErrorActionPreference = "Stop"

$displayName = -join [char[]](0x516D, 0x89D2, 0x4EE3, 0x7406)
$installDir = Join-Path $env:LOCALAPPDATA "Programs\HexagonProxy"
$appPath = Join-Path $installDir "HexagonProxy.exe"
$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Get-Process -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -eq $appPath } catch { $false }
} | Stop-Process -Force

Copy-Item -LiteralPath (Join-Path $sourceRoot "HexagonProxy.exe") -Destination $appPath -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot "LICENSE") -Destination $installDir -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot "LICENSING.md") -Destination $installDir -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot "SOURCE.md") -Destination $installDir -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot "THIRD_PARTY_NOTICES.md") -Destination $installDir -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot "Mihomo-LICENSE.txt") -Destination $installDir -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot "MetaRules-LICENSE.txt") -Destination $installDir -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot "uninstall.ps1") -Destination $installDir -Force

$shell = New-Object -ComObject WScript.Shell
$desktopShortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Desktop")) ($displayName + ".lnk")))
$desktopShortcut.TargetPath = $appPath
$desktopShortcut.WorkingDirectory = $installDir
$desktopShortcut.Description = $displayName
$desktopShortcut.Save()

$programsDir = Join-Path ([Environment]::GetFolderPath("Programs")) $displayName
New-Item -ItemType Directory -Force -Path $programsDir | Out-Null
$startShortcut = $shell.CreateShortcut((Join-Path $programsDir ($displayName + ".lnk")))
$startShortcut.TargetPath = $appPath
$startShortcut.WorkingDirectory = $installDir
$startShortcut.Description = $displayName
$startShortcut.Save()

$uninstallText = (-join [char[]](0x5378, 0x8F7D)) + $displayName
$uninstallShortcut = $shell.CreateShortcut((Join-Path $programsDir ($uninstallText + ".lnk")))
$uninstallShortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$uninstallShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $installDir 'uninstall.ps1')`""
$uninstallShortcut.WorkingDirectory = $installDir
$uninstallShortcut.Description = $uninstallText
$uninstallShortcut.Save()

Start-Process -FilePath $appPath
