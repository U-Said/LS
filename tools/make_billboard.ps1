# Renders the README pictures and the English catalog screenshots with headless Edge or Chrome:
#   tools/billboard.html   -> docs/billboard.png (RU), docs/billboard-en.png (EN)
#   tools/demo.html        -> docs/demo.png (RU),      docs/demo-en.png (EN)
#   tools/screenshots.html -> docs/screenshot-menu-en.png, screenshot-fix-en.png, screenshot-macos-en.png (1280x800)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$browser = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
             "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
             "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
             "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
             "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { throw 'Neither Edge nor Chrome is installed' }
$profileDir = Join-Path $env:TEMP 'ls-billboard-browser'
$shots = @(
    @{ page = 'billboard.html'; q = '?ru'; out = 'billboard.png';    h = 1135 },
    @{ page = 'billboard.html'; q = '?en'; out = 'billboard-en.png'; h = 1090 },
    @{ page = 'demo.html';      q = '?ru'; out = 'demo.png';         h = 560 },
    @{ page = 'demo.html';      q = '?en'; out = 'demo-en.png';      h = 560 },
    @{ page = 'screenshots.html'; q = '?menu'; out = 'screenshot-menu-en.png';  w = 1280; h = 800 },
    @{ page = 'screenshots.html'; q = '?fix';  out = 'screenshot-fix-en.png';   w = 1280; h = 800 },
    @{ page = 'screenshots.html'; q = '?mac';  out = 'screenshot-macos-en.png'; w = 1280; h = 800 }
)
$only = $args   # e.g. make_billboard.ps1 demo.png: only these pictures
if ($only.Count) { $shots = $shots | Where-Object { $only -contains $_.out } }
foreach ($v in $shots) {
    $page = ([Uri](Join-Path $PSScriptRoot $v.page)).AbsoluteUri
    $out = Join-Path $root "docs\$($v.out)"
    $w = if ($v.w) { $v.w } else { 1200 }
    $cli = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
             "--user-data-dir=`"$profileDir`"", '--force-device-scale-factor=1', "--window-size=$w,$($v.h)",
             "--screenshot=`"$out`"", "`"$page$($v.q)`"")
    Start-Process -FilePath $browser -ArgumentList $cli -Wait -WindowStyle Hidden
    Write-Host "$out $((Get-Item $out).Length) bytes"
}
