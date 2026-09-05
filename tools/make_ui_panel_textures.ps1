$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'assets\ui'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$themes = @{
    blue = @{
        surface=@('#dff5f7','#86c7df','#ffffff','#8cdcf2'); surface2=@('#cbeaf2','#71b9d5','#f8ffff','#72d3ec');
        crystal=@('#f4fcff','#a8dcec','#ffffff','#a7e9f8'); sidebar=@('#dceff2','#78b8cf','#f7ffff','#75d0e8');
        input=@('#f5fdff','#74bad4','#ffffff','#77daf0'); console=@('#0b2634','#4286a0','#183a49','#4bc5e5')
    }
    dark = @{
        surface=@('#182a37','#45667a','#203a49','#4e89a5'); surface2=@('#223846','#4d7185','#294856','#5aa2be');
        crystal=@('#13232f','#426276','#1b3341','#4c8aa5'); sidebar=@('#10222e','#365c71','#183443','#447f99');
        input=@('#101e29','#3f6376','#172d3b','#4b8aa4'); console=@('#07121a','#2c5368','#0d2634','#3789aa')
    }
}
foreach ($themeName in $themes.Keys) {
    foreach ($role in $themes[$themeName].Keys) {
        $c = $themes[$themeName][$role]
        $svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="$($c[0])" stop-opacity="0.96"/>
      <stop offset="1" stop-color="$($c[2])" stop-opacity="0.88"/>
    </linearGradient>
    <linearGradient id="edge" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="$($c[1])" stop-opacity="0.82"/>
      <stop offset="1" stop-color="$($c[3])" stop-opacity="0.66"/>
    </linearGradient>
  </defs>
  <rect x="2" y="2" width="124" height="124" rx="18" fill="url(#bg)" stroke="url(#edge)" stroke-width="2"/>
  <path d="M18 21 C36 13 55 15 72 19 C92 24 105 17 116 13" fill="none" stroke="$($c[3])" stroke-opacity="0.20" stroke-width="2"/>
  <path d="M11 105 C28 99 41 101 56 106 C78 113 99 108 118 101" fill="none" stroke="$($c[1])" stroke-opacity="0.22" stroke-width="2"/>
  <circle cx="108" cy="28" r="3" fill="$($c[3])" fill-opacity="0.18"/>
  <circle cx="98" cy="37" r="1.5" fill="$($c[3])" fill-opacity="0.22"/>
  <circle cx="21" cy="92" r="2" fill="$($c[1])" fill-opacity="0.16"/>
  <rect x="8" y="8" width="112" height="112" rx="14" fill="none" stroke="#ffffff" stroke-opacity="0.08"/>
</svg>
"@
        $path = Join-Path $outDir ("panel_{0}_{1}.svg" -f $themeName, $role)
        [IO.File]::WriteAllText($path, $svg, [Text.UTF8Encoding]::new($false))
    }
}
Write-Output "Generated panel textures in $outDir"
