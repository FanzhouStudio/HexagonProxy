$ErrorActionPreference = 'Stop'

$projectPath = $PSScriptRoot
$candidates = @(
    (Join-Path $projectPath 'Godot_v4.7-stable_win64.exe'),
    'D:\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe'
)

$godot = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $godot) {
    throw '未找到 Godot 4.7。请把 Godot_v4.7-stable_win64.exe 放到本目录，或用 Godot 项目管理器打开本项目。'
}

Start-Process -FilePath $godot -ArgumentList @('--path', $projectPath)
