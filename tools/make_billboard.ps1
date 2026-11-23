# Renders the README pictures with headless Edge or Chrome:
#   tools/billboard.html -> docs/billboard.png (RU), docs/billboard-en.png (EN)
#   tools/demo.html      -> docs/demo.png (RU),      docs/demo-en.png (EN)
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
    @{ page = 'billboard.html'; q = '?ru'; out = 'billboard.png';    h = 1110 },
    @{ page = 'billboard.html'; q = '?en'; out = 'billboard-en.png'; h = 1068 },
    @{ page = 'demo.html';      q = '?ru'; out = 'demo.png';         h = 560 },
    @{ page = 'demo.html';      q = '?en'; out = 'demo-en.png';      h = 560 }
)
foreach ($v in $shots) {
    $page = ([Uri](Join-Path $PSScriptRoot $v.page)).AbsoluteUri
    $out = Join-Path $root "docs\$($v.out)"
    $args = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
              "--user-data-dir=`"$profileDir`"", '--force-device-scale-factor=1', "--window-size=1200,$($v.h)",
              "--screenshot=`"$out`"", "`"$page$($v.q)`"")
    Start-Process -FilePath $browser -ArgumentList $args -Wait -WindowStyle Hidden
    Write-Host "$out $((Get-Item $out).Length) bytes"
}
