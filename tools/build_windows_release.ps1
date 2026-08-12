param(
    [string]$GodotPath = "D:\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$distDir = Join-Path $projectRoot "dist"
$buildDir = Join-Path $projectRoot "build"
$packagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("hexagon_proxy_iexpress_" + $PID)
$stagingDir = Join-Path $packagingDir "payload"
$appName = -join [char[]](0x516D, 0x89D2, 0x4EE3, 0x7406)
$installerSuffix = -join [char[]](0x5B89, 0x88C5, 0x5305)
$portablePath = Join-Path $distDir ($appName + ".exe")
$installerPath = Join-Path $distDir ($appName + $installerSuffix + ".exe")
$corePath = Join-Path $projectRoot "bin\mihomo.exe"
$templatePath = Join-Path $projectRoot "installer\package.sed"
$generatedSedPath = Join-Path $packagingDir "package.generated.sed"
$temporaryInstallerPath = Join-Path $packagingDir "HexagonProxySetup.exe"

if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot was not found: $GodotPath"
}
if (-not (Test-Path -LiteralPath $corePath)) {
    throw "Mihomo was not found: $corePath"
}

New-Item -ItemType Directory -Force -Path $distDir, $buildDir, $stagingDir | Out-Null

Write-Host "[1/4] Running automated tests"
& $GodotPath --headless --path $projectRoot --script res://tests/test_runner.gd
if ($LASTEXITCODE -ne 0) { throw "Base tests failed with exit code $LASTEXITCODE" }
& $GodotPath --headless --path $projectRoot --script res://tests/test_large_subscription_ui.gd
if ($LASTEXITCODE -ne 0) { throw "Large subscription test failed with exit code $LASTEXITCODE" }
& $GodotPath --headless --path $projectRoot --script res://tests/test_close_behavior.gd
if ($LASTEXITCODE -ne 0) { throw "Close behavior test failed with exit code $LASTEXITCODE" }

Write-Host "[2/4] Exporting portable application"
Remove-Item -LiteralPath $portablePath -Force -ErrorAction SilentlyContinue
& $GodotPath --headless --path $projectRoot --export-release "Windows Desktop" $portablePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $portablePath)) {
    throw "Godot export failed"
}

Write-Host "[3/4] Preparing installer payload"
Get-ChildItem -LiteralPath $stagingDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Copy-Item -LiteralPath $portablePath -Destination (Join-Path $stagingDir "HexagonProxy.exe") -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "LICENSE") -Destination $stagingDir -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "THIRD_PARTY_NOTICES.md") -Destination $stagingDir -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "third_party\Mihomo-LICENSE.txt") -Destination $stagingDir -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "installer\install.ps1") -Destination $stagingDir -Force
Copy-Item -LiteralPath (Join-Path $projectRoot "installer\uninstall.ps1") -Destination $stagingDir -Force

$sourceForSed = $stagingDir.TrimEnd("\") + "\"
$sed = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
$sed = $sed.Replace("__TARGET_PATH__", $temporaryInstallerPath).Replace("__SOURCE_PATH__", $sourceForSed)
Set-Content -LiteralPath $generatedSedPath -Value $sed -Encoding Default

Write-Host "[4/4] Creating installer"
Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $temporaryInstallerPath -Force -ErrorAction SilentlyContinue
& "$env:SystemRoot\System32\iexpress.exe" /N $generatedSedPath
$deadline = [DateTime]::UtcNow.AddMinutes(3)
$lastLength = -1
$stableChecks = 0
while ([DateTime]::UtcNow -lt $deadline -and $stableChecks -lt 3) {
    Start-Sleep -Seconds 1
    if (-not (Test-Path -LiteralPath $temporaryInstallerPath)) { continue }
    $currentLength = (Get-Item -LiteralPath $temporaryInstallerPath).Length
    if ($currentLength -gt 0 -and $currentLength -eq $lastLength) {
        $stableChecks++
    } else {
        $stableChecks = 0
        $lastLength = $currentLength
    }
}
if (-not (Test-Path -LiteralPath $temporaryInstallerPath) -or $stableChecks -lt 3) {
    throw "IExpress packaging failed"
}
Move-Item -LiteralPath $temporaryInstallerPath -Destination $installerPath -Force

$portable = Get-Item -LiteralPath $portablePath
$installer = Get-Item -LiteralPath $installerPath
$portableHash = (Get-FileHash -LiteralPath $portablePath -Algorithm SHA256).Hash
$installerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
$checksumPath = Join-Path $distDir "SHA256SUMS.txt"
$checksumLines = @(
    "$portableHash *$($portable.Name)"
    "$installerHash *$($installer.Name)"
)
Set-Content -LiteralPath $checksumPath -Value $checksumLines -Encoding UTF8

Write-Host ""
Write-Host "Release completed:"
Write-Host ("  Portable: {0} ({1:N1} MB)" -f $portable.FullName, ($portable.Length / 1MB))
Write-Host ("  SHA256:  {0}" -f $portableHash)
Write-Host ("  Installer: {0} ({1:N1} MB)" -f $installer.FullName, ($installer.Length / 1MB))
Write-Host ("  SHA256:   {0}" -f $installerHash)

Remove-Item -LiteralPath $packagingDir -Recurse -Force -ErrorAction SilentlyContinue
