# Renders tools/billboard.html into docs/billboard.png (RU) and docs/billboard-en.png (EN) with headless Edge.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
          "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$page = ([Uri](Join-Path $PSScriptRoot 'billboard.html')).AbsoluteUri
$profileDir = Join-Path $env:TEMP 'ls-billboard-edge'
foreach ($v in @(@{ q = '?ru'; out = 'billboard.png'; h = 1110 }, @{ q = '?en'; out = 'billboard-en.png'; h = 1068 })) {
    $out = Join-Path $root "docs\$($v.out)"
    $args = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
              "--user-data-dir=`"$profileDir`"", '--force-device-scale-factor=1', "--window-size=1200,$($v.h)",
              "--screenshot=`"$out`"", "`"$page$($v.q)`"")
    Start-Process -FilePath $edge -ArgumentList $args -Wait -WindowStyle Hidden
    Write-Host "$out $((Get-Item $out).Length) bytes"
}
