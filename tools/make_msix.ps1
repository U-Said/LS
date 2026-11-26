# Builds the Microsoft Store package of FastRevers from ready FastRevers.exe files:
#   FastRevers-<version>-x64.msix, FastRevers-<version>-arm64.msix and, with both, FastRevers-<version>.msixbundle
# (the bundle is what goes to Partner Center; the Store signs it). Next to them stay the unpacked layouts,
# which `Add-AppxPackage -Register <layout>\AppxManifest.xml` installs for a test (needs Developer Mode).
#   powershell -File tools/make_msix.ps1 -Exe build\FastRevers.exe -ExeArm64 arm64\FastRevers.exe `
#     -IdentityName <Package/Identity/Name> -Publisher <Package/Identity/Publisher> -PublisherDisplayName <name>
# The three identity values are on Partner Center > the app > Product identity; without them a test identity is used.
param(
    [string]$Exe,
    [string]$ExeArm64,
    [string]$OutDir = 'build\msix',
    [string]$IdentityName = 'FastRevers.Test',
    [string]$Publisher = 'CN=FastRevers Test',
    [string]$PublisherDisplayName = 'U-Said'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
if (-not $Exe -and -not $ExeArm64) { throw 'Give -Exe (x64) and/or -ExeArm64' }

# Windows SDK tools of the newest installed SDK, for the architecture of this PC
$hostArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
$sdkBin = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.*" -Directory |
    Where-Object { Test-Path "$($_.FullName)\$hostArch\makeappx.exe" } |
    Sort-Object { [version]$_.Name } | Select-Object -Last 1
if (-not $sdkBin) { throw 'makeappx.exe not found: install the Windows 10/11 SDK' }
$makeappx = "$($sdkBin.FullName)\$hostArch\makeappx.exe"
$makepri = "$($sdkBin.FullName)\$hostArch\makepri.exe"
function Invoke-Tool([string]$tool, [string[]]$arguments) {
    $out = & $tool @arguments 2>&1
    if ($LASTEXITCODE) { $out | Write-Host; throw "$(Split-Path $tool -Leaf) failed ($LASTEXITCODE)" }
}

$cmake = Get-Content "$root\CMakeLists.txt" -Raw
if ($cmake -notmatch 'project\(FastRevers VERSION (\d+\.\d+\.\d+)') { throw 'version not found in CMakeLists.txt' }
$version = "$($Matches[1]).0"   # the Store wants the fourth number to be 0
if (-not [IO.Path]::IsPathRooted($OutDir)) { $OutDir = Join-Path (Get-Location) $OutDir }
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force $OutDir | Out-Null

# ---- pictures for Start, the taskbar and the Store, from the icon sources in art/
function New-Png([string]$src, [int]$size, [double]$fill, [string]$path) {
    $img = [Drawing.Image]::FromFile($src)
    $bmp = New-Object Drawing.Bitmap $size, $size
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([Drawing.Color]::Transparent)
    $side = [int][Math]::Round($size * $fill)
    $off = [int](($size - $side) / 2)
    $g.DrawImage($img, (New-Object Drawing.Rectangle $off, $off, $side, $side))
    $g.Dispose(); $img.Dispose()
    $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
$assets = Join-Path $OutDir 'Assets'
Remove-Item -Recurse -Force $assets -ErrorAction SilentlyContinue
New-Item -ItemType Directory $assets | Out-Null
$master = "$root\art\ls-1024.png"
foreach ($s in @{ 100 = 44; 125 = 55; 150 = 66; 200 = 88; 400 = 176 }.GetEnumerator()) {
    New-Png $master $s.Value 1.0 "$assets\Square44x44Logo.scale-$($s.Key).png"
}
foreach ($t in 16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 256) {   # drawn for each size, used as they are
    Copy-Item "$root\art\ls-$t.png" "$assets\Square44x44Logo.targetsize-$t.png"
    Copy-Item "$root\art\ls-$t.png" "$assets\Square44x44Logo.targetsize-$($t)_altform-unplated.png"
}
foreach ($s in @{ 100 = 150; 125 = 188; 150 = 225; 200 = 300; 400 = 600 }.GetEnumerator()) {
    New-Png $master $s.Value 0.8 "$assets\Square150x150Logo.scale-$($s.Key).png"
}
foreach ($s in @{ 100 = 50; 125 = 63; 150 = 75; 200 = 100; 400 = 200 }.GetEnumerator()) {
    New-Png $master $s.Value 1.0 "$assets\StoreLogo.scale-$($s.Key).png"
}

# ---- one package per architecture
function Test-Machine([string]$file, [int]$want) {
    $b = [IO.File]::ReadAllBytes($file)
    $machine = [BitConverter]::ToUInt16($b, [BitConverter]::ToInt32($b, 0x3C) + 4)
    if ($machine -ne $want) { throw ('{0}: machine 0x{1:X4}, expected 0x{2:X4}' -f $file, $machine, $want) }
}
$esc = { param($s) [Security.SecurityElement]::Escape($s) }
$template = Get-Content "$root\windows\msix\AppxManifest.xml" -Raw
$packages = Join-Path $OutDir 'packages'
Remove-Item -Recurse -Force $packages -ErrorAction SilentlyContinue
New-Item -ItemType Directory $packages | Out-Null
$built = @()
foreach ($p in @(@{ arch = 'x64'; exe = $Exe; machine = 0x8664 }, @{ arch = 'arm64'; exe = $ExeArm64; machine = 0xAA64 })) {
    if (-not $p.exe) { continue }
    $exePath = (Resolve-Path $p.exe).Path
    Test-Machine $exePath $p.machine
    $layout = Join-Path $OutDir "layout-$($p.arch)"
    Remove-Item -Recurse -Force $layout -ErrorAction SilentlyContinue
    New-Item -ItemType Directory $layout | Out-Null
    Copy-Item $exePath "$layout\FastRevers.exe"
    Copy-Item $assets "$layout\Assets" -Recurse
    $manifest = $template.Replace('{{IdentityName}}', (& $esc $IdentityName)).Replace('{{Publisher}}', (& $esc $Publisher)).
        Replace('{{PublisherDisplayName}}', (& $esc $PublisherDisplayName)).Replace('{{Version}}', $version).Replace('{{Arch}}', $p.arch)
    [IO.File]::WriteAllText("$layout\AppxManifest.xml", $manifest, (New-Object Text.UTF8Encoding $false))
    # resources.pri lets Windows pick the right picture size (scale-*, targetsize-*)
    $priConfig = Join-Path $OutDir 'priconfig.xml'
    Invoke-Tool $makepri @('createconfig', '/cf', $priConfig, '/dq', 'en-US', '/pv', '10.0.0', '/o')
    [xml]$cfg = Get-Content $priConfig -Raw   # one resources.pri with every size, no split resource packs
    $cfg.SelectNodes('//packaging') | ForEach-Object { [void]$_.ParentNode.RemoveChild($_) }
    $cfg.Save($priConfig)
    Invoke-Tool $makepri @('new', '/pr', $layout, '/cf', $priConfig, '/mn', "$layout\AppxManifest.xml", '/of', "$layout\resources.pri", '/o')
    Remove-Item $priConfig
    $msix = Join-Path $packages "FastRevers-$($version -replace '\.0$')-$($p.arch).msix"
    Invoke-Tool $makeappx @('pack', '/d', $layout, '/p', $msix, '/o')
    $built += $msix
    Write-Host "$msix $((Get-Item $msix).Length) bytes"
}
if ($built.Count -eq 2) {
    $bundle = Join-Path $OutDir "FastRevers-$($version -replace '\.0$').msixbundle"
    Invoke-Tool $makeappx @('bundle', '/d', $packages, '/p', $bundle, '/bv', $version, '/o')
    Write-Host "$bundle $((Get-Item $bundle).Length) bytes"
}
Remove-Item -Recurse -Force $assets
