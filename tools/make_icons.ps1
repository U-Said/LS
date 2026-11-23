# Builds the app icons from art/ls-<size>.png (the "LS toggle, Graphite" artwork; art/ls.svg is the
# master drawing, art/ls-small.svg the bolder variant the 16–32 px PNGs are drawn from):
#   windows/LS.ico      — all 16 Windows 11 sizes: up to 48 px as plain BMP frames (tray, menus, small views),
#                         60…256 px as PNG frames to keep LS.exe small
#   macos/LS.iconset/   — PNG set for iconutil (the .icns itself is made on the Mac by macos/build.sh)
# A size with no PNG in art/ is scaled down from art/ls-1024.png.
# Run from anywhere: powershell -File tools/make_icons.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$art = Join-Path $root 'art'

function Load([int]$size) {
    $p = Join-Path $art "ls-$size.png"
    if (Test-Path $p) { return [System.Drawing.Bitmap]::new($p) }
    # missing size: scale down the 1024 master
    $src = [System.Drawing.Bitmap]::new((Join-Path $art 'ls-1024.png'))
    $bmp = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'; $g.CompositingQuality = 'HighQuality'
    $g.DrawImage($src, 0, 0, $size, $size)
    $g.Dispose(); $src.Dispose()
    return $bmp
}

function DibBytes([System.Drawing.Bitmap]$bmp) {
    $w = $bmp.Width; $h = $bmp.Height
    $rect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
    $data = $bmp.LockBits($rect, 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $px = New-Object byte[] ($w * $h * 4)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $px, 0, $px.Length)
    $bmp.UnlockBits($data)
    $maskRow = [int]([Math]::Ceiling($w / 32.0) * 4)
    $ms = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter $ms
    $bw.Write([int]40); $bw.Write([int]$w); $bw.Write([int]($h * 2)); $bw.Write([int16]1); $bw.Write([int16]32)
    $bw.Write([int]0); $bw.Write([int]($w * $h * 4 + $maskRow * $h)); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0)
    for ($y = $h - 1; $y -ge 0; $y--) { $bw.Write($px, $y * $w * 4, $w * 4) }   # bottom-up BGRA
    $bw.Write((New-Object byte[] ($maskRow * $h)))                               # AND mask: alpha is used instead
    $bw.Flush()
    return , $ms.ToArray()
}

function PngBytes([System.Drawing.Bitmap]$bmp) {
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    return , $ms.ToArray()
}

# ---------------------------------------------------------------- Windows .ico
$sizes = 16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 128, 192, 256
$frames = foreach ($s in $sizes) {
    $b = Load $s
    [byte[]]$bytes = if ($s -gt 48) { PngBytes $b } else { DibBytes $b }
    $b.Dispose()
    , @($s, $bytes)
}
$ms = New-Object IO.MemoryStream
$bw = New-Object IO.BinaryWriter $ms
$bw.Write([int16]0); $bw.Write([int16]1); $bw.Write([int16]$frames.Count)
$offset = 6 + 16 * $frames.Count
foreach ($f in $frames) {
    $s = $f[0]; $len = $f[1].Length
    $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([int16]1); $bw.Write([int16]32); $bw.Write([int]$len); $bw.Write([int]$offset)
    $offset += $len
}
foreach ($f in $frames) { $bw.Write([byte[]]$f[1]) }
$bw.Flush()
[IO.File]::WriteAllBytes((Join-Path $root 'windows\LS.ico'), $ms.ToArray())
"windows\LS.ico: $($frames.Count) frames, $($ms.Length) bytes"

# ---------------------------------------------------------------- macOS iconset
$set = Join-Path $root 'macos\LS.iconset'
New-Item -ItemType Directory -Force $set | Out-Null
$names = @{ 'icon_16x16.png' = 16; 'icon_16x16@2x.png' = 32; 'icon_32x32.png' = 32; 'icon_32x32@2x.png' = 64;
            'icon_128x128.png' = 128; 'icon_128x128@2x.png' = 256; 'icon_256x256.png' = 256;
            'icon_256x256@2x.png' = 512; 'icon_512x512.png' = 512; 'icon_512x512@2x.png' = 1024 }
foreach ($n in $names.Keys) {
    $b = Load $names[$n]
    $b.Save((Join-Path $set $n), [System.Drawing.Imaging.ImageFormat]::Png)
    $b.Dispose()
}
"macos\LS.iconset: $($names.Count) files"
