# Draws the small sizes of the FastRevers icon (16...40 px) as clean pixel art: the full "tablo" picture
# (art/tablo, art/fr-1024.png) turns to mush that small, so here the board is simpler and taller, the letters
# are as big as the size allows, and the frame is light enough to stand out on a dark taskbar.
#   art/fr-16.png ... art/fr-40.png   (tools/make_icons.ps1 takes them as they are)
# Letters: the designer's font art/tablo/source/FastRevers-Display-Bold.ttf (OFL, from Noto Sans Bold).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$art = Join-Path $root 'art'
$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$fonts.AddFontFile((Join-Path $art 'tablo\source\FastRevers-Display-Bold.ttf'))
$family = $fonts.Families[0]

$frame = [System.Drawing.Color]::FromArgb(255, 0x8A, 0x87, 0x84)    # light rim: visible on dark and light bars
$body = [System.Drawing.Color]::FromArgb(255, 0x3A, 0x39, 0x38)
$flap = [System.Drawing.Color]::FromArgb(255, 0x24, 0x24, 0x24)
$cream = [System.Drawing.Color]::FromArgb(255, 0xF7, 0xEC, 0xD5)
$orange = [System.Drawing.Color]::FromArgb(255, 0xFD, 0xA5, 0x51)

function RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure(); return $p
}

# a letter filling (part of) a box, snapped to whole pixels
function Letter($g, [string]$ch, [System.Drawing.RectangleF]$box, $color) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddString($ch, $family, [int][System.Drawing.FontStyle]::Regular, 100, [System.Drawing.PointF]::new(0, 0), [System.Drawing.StringFormat]::GenericTypographic)
    $b = $p.GetBounds()
    $scale = [Math]::Min($box.Height / $b.Height, $box.Width / $b.Width)
    $w = $b.Width * $scale; $h = $b.Height * $scale
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate([Math]::Round($box.X + ($box.Width - $w) / 2), [Math]::Round($box.Y + ($box.Height - $h) / 2))
    $m.Scale($scale, $scale); $m.Translate(-$b.X, -$b.Y)
    $p.Transform($m)
    $g.FillPath((New-Object System.Drawing.SolidBrush $color), $p)
}

foreach ($s in 16, 20, 24, 30, 32, 36, 40) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'Half'; $g.Clear([System.Drawing.Color]::Transparent)
    $h = [Math]::Round($s * 0.78)                       # taller than the 1024 picture (0.56) so letters can grow
    $y = [Math]::Floor(($s - $h) / 2)
    $r = [Math]::Max(2, $s * 0.16)
    $g.FillPath((New-Object System.Drawing.SolidBrush $frame), (RoundRect 0 $y $s $h $r))
    $g.FillPath((New-Object System.Drawing.SolidBrush $body), (RoundRect 1 ($y + 1) ($s - 2) ($h - 2) ($r - 1)))
    $pad = if ($s -ge 30) { 3 } else { 2 }; $gap = if ($s -ge 30) { 2 } else { 1 }
    $fw = ($s - 2 * $pad - $gap) / 2; $fh = $h - 2 * $pad
    foreach ($i in 0, 1) {
        $fx = $pad + $i * ($fw + $gap)
        $g.FillRectangle((New-Object System.Drawing.SolidBrush $flap), [float]$fx, [float]($y + $pad), [float]$fw, [float]$fh)
        $inset = if ($s -ge 30) { 2 } else { 1 }
        $box = [System.Drawing.RectangleF]::new($fx + $inset, $y + $pad + $inset, $fw - 2 * $inset, $fh - 2 * $inset)
        Letter $g @('F', 'R')[$i] $box @($cream, $orange)[$i]
    }
    $g.Dispose()
    $out = Join-Path $art "fr-$s.png"
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    "$out"
}
