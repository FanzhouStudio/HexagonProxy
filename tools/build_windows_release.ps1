param(
    [string]$GodotPath = "D:\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$distDir = Join-Path $projectRoot "dist"
$buildDir = Join-Path $projectRoot "build"
$packagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("hexagon_proxy_iexpress_" + $PID)
$stagingDir = Join-Path $packagingDir "payload"
$portablePath = Join-Path $distDir "HexagonProxy.exe"
$stagedPortable = Join-Path $stagingDir "HexagonProxy.exe"

if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot was not found: $GodotPath"
}

New-Item -ItemType Directory -Force -Path $distDir, $buildDir, $stagingDir | Out-Null

function Invoke-IsolatedGodotTest {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [string]$FailureMessage
    )

    $testRoot = Join-Path $packagingDir ("test_data_" + $Name)
    $testRoaming = Join-Path $testRoot "Roaming"
    $testLocal = Join-Path $testRoot "Local"
    New-Item -ItemType Directory -Force -Path $testRoaming, $testLocal | Out-Null

    $originalAppData = $env:APPDATA
    $originalLocalAppData = $env:LOCALAPPDATA
    $exitCode = 1
    try {
        $env:APPDATA = $testRoaming
        $env:LOCALAPPDATA = $testLocal
        & $GodotPath --headless --path $projectRoot --script $ScriptPath
        $exitCode = $LASTEXITCODE
    } finally {
        $env:APPDATA = $originalAppData
        $env:LOCALAPPDATA = $originalLocalAppData
    }
    if ($exitCode -ne 0) { throw "$FailureMessage with exit code $exitCode" }
}

& $GodotPath --headless --path $projectRoot --editor --import
if ($LASTEXITCODE -ne 0) { throw "Godot import failed" }
Write-Host "[1/2] Running automated tests"
Invoke-IsolatedGodotTest "base" "res://tests/test_runner.gd" "Base tests failed"
Invoke-IsolatedGodotTest "core_stability" "res://tests/test_core_stability.gd" "Core stability tests failed"
Invoke-IsolatedGodotTest "proxy_health" "res://tests/test_proxy_health.gd" "Proxy health tests failed"
Invoke-IsolatedGodotTest "tun_profile" "res://tests/test_tun_profile_transformer.gd" "TUN profile tests failed"
Invoke-IsolatedGodotTest "runtime_coordinator" "res://tests/test_runtime_coordinator.gd" "Runtime coordinator tests failed"
Invoke-IsolatedGodotTest "routing_rules" "res://tests/test_routing_rules.gd" "Routing rules tests failed"
Invoke-IsolatedGodotTest "large_subscription" "res://tests/test_large_subscription_ui.gd" "Large subscription test failed"
Invoke-IsolatedGodotTest "close_behavior" "res://tests/test_close_behavior.gd" "Close behavior test failed"
Invoke-IsolatedGodotTest "hysteria2" "res://tests/test_hysteria2_conversion.gd" "Hysteria2 conversion test failed"
Invoke-IsolatedGodotTest "ui_theme" "res://tests/test_ui_theme.gd" "UI texture/theme test failed"
Invoke-IsolatedGodotTest "layout_1080" "res://tests/test_layout_1080.gd" "1920x1080 layout test failed"
Invoke-IsolatedGodotTest "node_failover" "res://tests/test_node_failover.gd" "Node failover test failed"
Invoke-IsolatedGodotTest "brand_identity" "res://tests/test_brand_identity.gd" "Brand identity test failed"
Invoke-IsolatedGodotTest "codex_profiles" "res://tests/test_codex_profile_service.gd" "Codex profile test failed"
Invoke-IsolatedGodotTest "codex_auto_refresh" "res://tests/test_codex_auto_refresh.gd" "Codex auto refresh tests failed"
Invoke-IsolatedGodotTest "codex_panel" "res://tests/test_codex_accounts_panel.gd" "Codex panel test failed"
& powershell.exe -NoProfile -File (Join-Path $projectRoot "tests\test_codex_helper.ps1")
if ($LASTEXITCODE -ne 0) { throw "Codex helper tests failed" }

Write-Host "[2/2] Exporting HexagonProxy.exe"
$exportOutput = & $GodotPath --headless --path $projectRoot --export-release "Windows Desktop" $stagedPortable 2>&1
$exportExit = $LASTEXITCODE
$exportOutput | Set-Content -LiteralPath (Join-Path $buildDir "export.log")
if ($exportExit -ne 0 -or ($exportOutput -match 'SCRIPT ERROR') -or -not (Test-Path -LiteralPath $stagedPortable)) {
    throw "Godot export failed; previous release was preserved. See build/export.log"
}
# Publish only after successful export. A running executable may prevent replacement.
Copy-Item -LiteralPath $stagedPortable -Destination $portablePath -Force

# Remove only previous application packages within the verified output directories.
foreach ($outputDir in @($distDir, $buildDir)) {
    $outputRoot = [IO.Path]::GetFullPath($outputDir).TrimEnd('\') + '\'
    foreach ($oldPackage in Get-ChildItem -LiteralPath $outputDir -Filter 'HexagonProxy*.exe' -File -Recurse) {
        $resolved = [IO.Path]::GetFullPath($oldPackage.FullName)
        if (-not $resolved.StartsWith($outputRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Unexpected package path: $resolved" }
        if ($resolved -ne $portablePath) { Remove-Item -LiteralPath $resolved -Force }
    }
}
$portableHash = (Get-FileHash -LiteralPath $portablePath -Algorithm SHA256).Hash
Set-Content -LiteralPath (Join-Path $distDir 'SHA256SUMS.txt') -Value "$portableHash *HexagonProxy.exe" -Encoding UTF8
Write-Host "Release completed: $portablePath"
Write-Host "SHA256: $portableHash"
# Temporary staging belongs exclusively to this invocation.
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$resolvedPackaging = [IO.Path]::GetFullPath($packagingDir)
if (-not $resolvedPackaging.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid staging path' }
Remove-Item -LiteralPath $resolvedPackaging -Recurse -Force
