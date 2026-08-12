$ErrorActionPreference = "SilentlyContinue"

$displayName = -join [char[]](0x516D, 0x89D2, 0x4EE3, 0x7406)
$installDir = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Programs\HexagonProxy"))
$expectedDir = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Programs\HexagonProxy"))
if ($installDir -ne $expectedDir) {
    exit 2
}

$appPath = Join-Path $installDir "HexagonProxy.exe"
$corePath = Join-Path $env:APPDATA ("Godot\app_userdata\" + $displayName + "\runtime\mihomo.exe")
Get-Process -Name "mihomo" -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -eq $corePath } catch { $false }
} | Stop-Process -Force
Get-Process | Where-Object {
    try { $_.Path -eq $appPath } catch { $false }
} | Stop-Process -Force

Remove-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "HexagonProxy" -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath("Desktop")) ($displayName + ".lnk")) -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath("Programs")) $displayName) -Recurse -Force -ErrorAction SilentlyContinue

$cleanup = @"
Start-Sleep -Seconds 2
`$target = [IO.Path]::GetFullPath('$($installDir.Replace("'", "''"))')
`$expected = [IO.Path]::GetFullPath((Join-Path `$env:LOCALAPPDATA 'Programs\HexagonProxy'))
if (`$target -eq `$expected) {
    for (`$attempt = 0; `$attempt -lt 10 -and (Test-Path -LiteralPath `$target); `$attempt++) {
        Remove-Item -LiteralPath `$target -Recurse -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}
"@
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cleanup))
Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -ArgumentList "-NoProfile", "-EncodedCommand", $encoded
