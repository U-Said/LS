# End-to-end check of LS.exe on this PC: starts LS, opens a test window and "types" into it with
# scan codes, exactly like a physical keyboard. Needs the Russian and English (US) layouts.
#   powershell -STA -File tools/e2e_windows.ps1 -Exe build\Release\LS.exe
# Takes about 20 seconds; do not type while it runs. Your clipboard is left as it was.
param([Parameter(Mandatory)][string]$Exe)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class K {
  [StructLayout(LayoutKind.Sequential)] struct KI { public ushort vk, sc; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size = 40)] struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, IN[] i, int size);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  static void Send(ushort vk, ushort sc, uint flags) {
    var i = new IN[1]; i[0].type = 1; i[0].ki.vk = vk; i[0].ki.sc = sc; i[0].ki.flags = flags;
    SendInput(1, i, Marshal.SizeOf(typeof(IN)));
  }
  public static void Scan(ushort sc, bool up) { Send(0, sc, 0x0008u | (up ? 0x0002u : 0u)); }   // KEYEVENTF_SCANCODE
  public static void Vk(ushort vk, bool up) { Send(vk, 0, up ? 0x0002u : 0u); }
  public static void Focus(IntPtr h) {
    uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero), me = GetCurrentThreadId();
    AttachThreadInput(me, fg, true); SetForegroundWindow(h); AttachThreadInput(me, fg, false);
  }
}
"@

# physical keys of the US layout
$sc = @{}
$rows = @{ 0x10 = 'qwertyuiop[]'; 0x1E = "asdfghjkl;'"; 0x2C = 'zxcvbnm,./' }
foreach ($start in $rows.Keys) { $i = 0; foreach ($c in $rows[$start].ToCharArray()) { $sc[[string]$c] = $start + $i; $i++ } }
$sc[' '] = 0x39
$shifted = @{ '?' = '/'; '<' = ','; '>' = '.'; ':' = ';'; '"' = "'"; '{' = '['; '}' = ']' }

function Pump([int]$ms) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $ms) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 5 }
}
function Ensure-Focus {
    if ([K]::GetForegroundWindow() -ne $form.Handle) { [K]::Focus($form.Handle); Pump 200 }
    if ([K]::GetForegroundWindow() -ne $form.Handle) { throw 'the test window lost focus' }
}
function Type-Keys([string]$keys) {
    Ensure-Focus
    foreach ($ch in $keys.ToCharArray()) {
        $c = [string]$ch; $shift = $false
        if ($shifted.ContainsKey($c)) { $c = $shifted[$c]; $shift = $true }
        elseif ($c -cmatch '[A-Z]') { $c = $c.ToLower(); $shift = $true }
        if ($shift) { [K]::Scan(0x2A, $false) }
        [K]::Scan($sc[$c], $false); [K]::Scan($sc[$c], $true)
        if ($shift) { [K]::Scan(0x2A, $true) }
        Pump 25
    }
    Pump 300
}
function Double-Shift { Ensure-Focus; foreach ($n in 1, 2) { [K]::Scan(0x2A, $false); Pump 40; [K]::Scan(0x2A, $true); Pump 90 }; Pump 300 }
function Press-Vk([int]$vk) { Ensure-Focus; [K]::Vk($vk, $false); [K]::Vk($vk, $true); Pump 300 }
function Layout { [System.Windows.Forms.InputLanguage]::CurrentInputLanguage.Culture.TwoLetterISOLanguageName }
function Set-En { [System.Windows.Forms.InputLanguage]::CurrentInputLanguage = [System.Windows.Forms.InputLanguage]::FromCulture([Globalization.CultureInfo]'en-US'); Pump 100 }
function Reset([string]$text = '') { $tb.Text = $text; $tb.SelectionStart = $tb.TextLength; Press-Vk 0x1B; Set-En }   # Esc: LS forgets the word

$script:fails = 0
function Check([string]$what, [string]$want, [string]$wantLayout) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    do {
        $got = $tb.Text; $lay = Layout
        $ok = ($got -ceq $want) -and (-not $wantLayout -or $lay -eq $wantLayout)
        if (-not $ok) { Pump 50 }
    } while (-not $ok -and $sw.ElapsedMilliseconds -lt 1500)
    if ($sw.ElapsedMilliseconds -gt 400) { $what += " ($($sw.ElapsedMilliseconds) ms)" }
    if (-not $ok) { $script:fails++ }
    "{0}  {1}: '{2}' [{3}]{4}" -f ($(if ($ok) { 'OK  ' } else { 'FAIL' })), $what, $got, $lay, $(if ($ok) { '' } else { "  (want '$want' [$wantLayout])" })
}

$exe = (Resolve-Path $Exe).Path
$dir = Split-Path $exe
$excFile = Join-Path $dir 'exceptions.txt'
Remove-Item $excFile -ErrorAction SilentlyContinue
Get-Process LS -ErrorAction SilentlyContinue | Where-Object Path -eq $exe | Stop-Process -Force
$ls = Start-Process $exe -PassThru
Start-Sleep -Milliseconds 1200

$clipBefore = if ([System.Windows.Forms.Clipboard]::ContainsText()) { [System.Windows.Forms.Clipboard]::GetText() } else { $null }
$form = New-Object System.Windows.Forms.Form
$form.Text = 'LS test - do not type'; $form.TopMost = $true; $form.Width = 520; $form.Height = 160; $form.StartPosition = 'CenterScreen'
$tb = New-Object System.Windows.Forms.TextBox
$tb.Multiline = $true; $tb.Dock = 'Fill'; $tb.Font = New-Object System.Drawing.Font('Segoe UI', 14)
$form.Controls.Add($tb)
try {
    $form.Show(); $form.Activate(); $tb.Focus() | Out-Null; Pump 400
    Reset
    Type-Keys 'ghbdtn ';            Check 'auto RU'                 'привет '            'ru'
    Type-Keys 'hello ';             Check 'auto EN'                 'привет hello '      'en'
    Type-Keys 'ghb'; Double-Shift;  Check 'double Shift'            'привет hello при'   'ru'
    Double-Shift;                   Check 'double Shift again'      'привет hello ghb'   'en'
    Reset; Type-Keys 'ghbdtn'; Press-Vk 0x13
                                    Check 'Pause'                   'привет'             'ru'
    Reset; Type-Keys 'HTTP ';       Check 'abbreviation kept'       'HTTP '              'en'
    Reset; Type-Keys 'printf hello world ';
                                    Check 'English kept'            'printf hello world ' 'en'
    Reset; Type-Keys 'vjcrdf ';     Check 'auto before learning'    'москва '            'ru'
    Double-Shift;                   Check 'undo auto-fix'           'vjcrdf '            'en'
    Type-Keys 'vjcrdf ';            Check 'learned word kept'       'vjcrdf vjcrdf '     'en'
    $learned = (Test-Path $excFile) -and ((Get-Content $excFile -Encoding UTF8) -contains 'vjcrdf')
    if (-not $learned) { $script:fails++ }; "{0}  exceptions.txt has the word" -f ($(if ($learned) { 'OK  ' } else { 'FAIL' }))
    Reset 'Ghbdtn? vbh!'; $tb.SelectAll(); Pump 100
    Ensure-Focus; [K]::Scan(0x2A, $false); [K]::Vk(0x13, $false); [K]::Vk(0x13, $true); [K]::Scan(0x2A, $true); Pump 1500
                                    Check 'Shift+Pause on selection' 'Привет, мир!'      'ru'
    $clipAfter = if ([System.Windows.Forms.Clipboard]::ContainsText()) { [System.Windows.Forms.Clipboard]::GetText() } else { $null }
    $same = $clipAfter -ceq $clipBefore
    if (-not $same) { $script:fails++ }; "{0}  clipboard restored" -f ($(if ($same) { 'OK  ' } else { 'FAIL' }))
} finally {
    $form.Close()
    Stop-Process -Id $ls.Id -Force -ErrorAction SilentlyContinue
    Remove-Item $excFile -ErrorAction SilentlyContinue
}
"$script:fails failed"
exit $script:fails
