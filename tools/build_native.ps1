param([switch]$Package,[switch]$SkipTests)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
$env:TEMP=Join-Path $root 'build/native-temp'
$env:TMP=$env:TEMP
$env:VSLANG='1033'
New-Item -ItemType Directory -Force $env:TEMP | Out-Null
$vswhere='C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe'
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(-not $vs){throw 'MSVC C++ build tools not found'}
$dev=Join-Path $vs 'Common7/Tools/VsDevCmd.bat'
$lines=& cmd.exe /d /s /c "`"$dev`" -no_logo -arch=x64 -host_arch=x64 >nul && set"
if($LASTEXITCODE -ne 0){throw 'MSVC environment setup failed'}
foreach($line in $lines){if($line -match '^([^=]+)=(.*)$'){[Environment]::SetEnvironmentVariable($matches[1],$matches[2],'Process')}}
$cmake=Join-Path $vs 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
$ninja=Join-Path $vs 'Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe'
$qt=Join-Path $root 'build/native-toolchain/Qt'
if(-not(Test-Path -LiteralPath (Join-Path $qt 'bin/Qt6Core.dll')) -or -not(Test-Path -LiteralPath (Join-Path $root 'build/native-toolchain/webview2/build/native/include/WebView2.h')) -or -not(Test-Path -LiteralPath (Join-Path $root 'build/native-toolchain/yaml-cpp/CMakeLists.txt'))){& node tools/setup_native_toolchain.mjs;if($LASTEXITCODE -ne 0){throw 'Qt/native dependency setup failed'}}
$env:PATH=(Join-Path $qt 'bin')+';'+$env:PATH
& $cmake -S $root -B (Join-Path $root 'build/native') -G Ninja '-DCMAKE_BUILD_TYPE=Release' "-DCMAKE_PREFIX_PATH=$qt" "-DCMAKE_MAKE_PROGRAM=$ninja"
if($LASTEXITCODE -ne 0){throw 'CMake configuration failed'}
& $cmake --build (Join-Path $root 'build/native') --parallel 6
if($LASTEXITCODE -ne 0){throw 'C++ build failed'}
$env:HEXAGON_RESOURCE_DIR=$root
$env:QT_PLUGIN_PATH=Join-Path $qt 'plugins'
if(-not $SkipTests){$test=Start-Process -FilePath (Join-Path $root 'build/native/hexagon_native_tests.exe') -ArgumentList '-platform offscreen' -WindowStyle Hidden -Wait -PassThru;if($test.ExitCode -ne 0){throw "Native tests failed: $($test.ExitCode)"}}
if($Package){& (Join-Path $PSScriptRoot 'package_native.ps1') -QtRoot $qt -CMakePath $cmake;if($LASTEXITCODE -ne 0){throw 'Native packaging failed'}}
