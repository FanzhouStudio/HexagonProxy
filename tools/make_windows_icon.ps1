param(
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\assets\axolotl.png'),
    [string]$OutputDir = (Join-Path $PSScriptRoot '..\assets')
)

Add-Type -AssemblyName System.Drawing
$sourceBitmap = [System.Drawing.Bitmap]::FromFile((Resolve-Path $SourcePath).Path)
$minX = $sourceBitmap.Width; $minY = $sourceBitmap.Height; $maxX = -1; $maxY = -1
for ($y = 0; $y -lt $sourceBitmap.Height; $y++) {
    for ($x = 0; $x -lt $sourceBitmap.Width; $x++) {
        if ($sourceBitmap.GetPixel($x, $y).A -gt 0) {
            if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
        }
    }
}
if ($maxX -lt 0) { throw 'Source image has no visible pixels.' }
$cropWidth = [int]($maxX - $minX + 1)
$cropHeight = [int]($maxY - $minY + 1)
$crop = [System.Drawing.Rectangle]::new([int]$minX, [int]$minY, $cropWidth, $cropHeight)
$mascot = $sourceBitmap.Clone($crop, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$sourceBitmap.Dispose()
function New-IconBitmap([int]$Size) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $maxW = [int]($Size * 0.91); $maxH = [int]($Size * 0.82)
    $scale = [Math]::Min($maxW / $mascot.Width, $maxH / $mascot.Height)
    $w = [Math]::Max(1, [int][Math]::Round($mascot.Width * $scale))
    $h = [Math]::Max(1, [int][Math]::Round($mascot.Height * $scale))
    $x = [int](($Size - $w) / 2); $y = [int](($Size - $h) / 2)
    $g.DrawImage($mascot, $x, $y, $w, $h)
    $g.Dispose()
    return $bmp
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$master = New-IconBitmap 256
$pngPath = Join-Path $OutputDir 'app_icon.png'
$master.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
$master.Dispose()
$sizes = @(16,24,32,48,64,128,256)
$entries = @()
foreach ($size in $sizes) {
    $bmp = New-IconBitmap $size
    $stream = New-Object System.IO.MemoryStream
    $bmp.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $entries += ,@($size, $stream.ToArray())
    $stream.Dispose()
}
$icoPath = Join-Path $OutputDir 'app_icon.ico'
$fs = [System.IO.File]::Open($icoPath, [System.IO.FileMode]::Create)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$entries.Count)
$offset = 6 + 16 * $entries.Count
foreach ($entry in $entries) {
    $size = [int]$entry[0]; $bytes = [byte[]]$entry[1]
    $bw.Write([byte]($(if ($size -eq 256) {0} else {$size})))
    $bw.Write([byte]($(if ($size -eq 256) {0} else {$size})))
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([UInt16]1); $bw.Write([UInt16]32)
    $bw.Write([UInt32]$bytes.Length); $bw.Write([UInt32]$offset)
    $offset += $bytes.Length
}
foreach ($entry in $entries) { $bw.Write([byte[]]$entry[1]) }
$bw.Dispose(); $fs.Dispose(); $mascot.Dispose()
Write-Output $pngPath
Write-Output $icoPath
