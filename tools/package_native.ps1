param([Parameter(Mandatory=$true)][string]$QtRoot,[Parameter(Mandatory=$true)][string]$CMakePath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$payload=Join-Path $root 'build/native-payload'
$resolved=[IO.Path]::GetFullPath($payload)
if(-not $resolved.StartsWith(([IO.Path]::GetFullPath((Join-Path $root 'build'))+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid payload path'}
if(Test-Path -LiteralPath $payload){Remove-Item -LiteralPath $payload -Recurse -Force}
New-Item -ItemType Directory -Force $payload | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'build/native/HexagonProxy.exe') -Destination $payload
& (Join-Path $QtRoot 'bin/windeployqt.exe') --release --no-translations --no-opengl-sw --no-system-d3d-compiler --no-compiler-runtime (Join-Path $payload 'HexagonProxy.exe')
if($LASTEXITCODE -ne 0){throw 'Qt deployment failed'}
# Use Microsoft's redistributable CRT files, never the compiler tool binaries.
$vs=& 'C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe' -latest -products '*' -property installationPath
$redist=Get-ChildItem (Join-Path $vs 'VC/Redist/MSVC') -Directory | Where-Object Name -Match '^\d' | Sort-Object Name -Descending | Select-Object -First 1
$crt=Get-ChildItem (Join-Path $redist.FullName 'x64') -Directory -Filter '*.CRT' | Select-Object -First 1
if(-not $crt){throw 'Official Microsoft redistributable CRT directory not found'}
Copy-Item -Path (Join-Path $crt.FullName '*.dll') -Destination $payload
$resources=Join-Path $payload 'resources'
New-Item -ItemType Directory -Force (Join-Path $resources 'scripts/linux'),(Join-Path $resources 'third_party/linux_runtime'),(Join-Path $resources 'third_party/antigravity-proxy'),(Join-Path $resources 'third_party/meta-rules-dat') | Out-Null
Get-ChildItem (Join-Path $root 'scripts') -Filter '*.ps1' -File | Copy-Item -Destination (Join-Path $resources 'scripts')
Get-ChildItem (Join-Path $root 'scripts/linux') -Filter '*.sh' -File | Copy-Item -Destination (Join-Path $resources 'scripts/linux')
foreach($folder in @('linux_runtime','antigravity-proxy','meta-rules-dat')){Get-ChildItem (Join-Path $root ('third_party/'+$folder)) -File | Where-Object Extension -NE '.tmp' | Copy-Item -Destination (Join-Path $resources ('third_party/'+$folder))}
foreach($file in @('LICENSE','LICENSING.md','THIRD_PARTY_NOTICES.md','SOURCE.md')){Copy-Item -LiteralPath (Join-Path $root $file) -Destination $resources}
Copy-Item -LiteralPath (Join-Path $root 'build/native-toolchain/yaml-cpp/LICENSE') -Destination (Join-Path $resources 'YAML-CPP-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $root 'build/native-toolchain/webview2/LICENSE.txt') -Destination (Join-Path $resources 'WEBVIEW2-LICENSE.txt')
if(Test-Path -LiteralPath (Join-Path $root 'third_party/qt')){Copy-Item -LiteralPath (Join-Path $root 'third_party/qt') -Destination (Join-Path $resources 'third_party') -Recurse}
$files=@(Get-ChildItem -LiteralPath $payload -File -Recurse | ForEach-Object {[IO.Path]::GetRelativePath($payload,$_.FullName).Replace('\','/')})
[IO.File]::WriteAllLines((Join-Path $payload 'files.list'),$files,[Text.UTF8Encoding]::new($false))
$zip=Join-Path $root 'build/native-payload.zip'
if(Test-Path -LiteralPath $zip){Remove-Item -LiteralPath $zip -Force}
$seven=Join-Path $root 'build/linux-runtime/7zip-full/7z.exe'
Push-Location -LiteralPath $payload
try{& $seven a -tzip -mx=1 -y $zip . | Out-Null;if($LASTEXITCODE -ne 0){throw 'Payload ZIP build failed'}}finally{Pop-Location}
& $CMakePath -S $root -B (Join-Path $root 'build/native') "-DHEXAGON_PAYLOAD_ZIP=$zip"
if($LASTEXITCODE -ne 0){throw 'Bootstrap configuration failed'}
& $CMakePath --build (Join-Path $root 'build/native') --target HexagonProxyBundle --parallel 4
if($LASTEXITCODE -ne 0){throw 'Bootstrap build failed'}
Write-Output (Join-Path $root 'build/native-bundle/HexagonProxy.exe')
