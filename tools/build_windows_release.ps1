param([switch]$SkipTests)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
if(-not(Test-Path -LiteralPath 'third_party/linux_runtime/runtime.zip')){
    & node tools/build_linux_runtime.mjs
    if($LASTEXITCODE -ne 0){throw 'Offline Linux runtime build failed'}
}
& ./tools/build_native.ps1 -Package -SkipTests:$SkipTests
if($LASTEXITCODE -ne 0){throw 'Native build or package failed'}
$dist=Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$target=Join-Path $dist 'HexagonProxy.exe'
$source=Join-Path $root 'build/native-bundle/HexagonProxy.exe'
if(-not(Test-Path -LiteralPath $source)){throw 'Native package not found; previous package preserved'}
try{Copy-Item -LiteralPath $source -Destination $target -Force}
catch{
    if(-not(Test-Path -LiteralPath $target)){throw}
    $saved=Join-Path $root ('build/HexagonProxy-'+[guid]::NewGuid().ToString('N')+'.running')
    Move-Item -LiteralPath $target -Destination $saved
    Copy-Item -LiteralPath $source -Destination $target
}
$hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
[IO.File]::WriteAllText((Join-Path $dist 'SHA256SUMS.txt'),"$hash *HexagonProxy.exe`n",[Text.UTF8Encoding]::new($false))
Write-Output "Native release: $target"
Write-Output "SHA256: $hash"
