# Install.ps1 - one-click desktop installer for DeepSeek Harness.
# Pins a copy of the harness into %LOCALAPPDATA%\DSHDesktop, generates a desktop
# icon (DSH.ico), and creates Desktop + Start Menu shortcuts.
# Re-run any time to update the pinned copy (e.g. after upgrading via npx).
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'DSHDesktop'),
    [string]$SourceRoot = '',
    [switch]$SkipIcon
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Write-Step { param([string]$Message) Write-Host "[*] $Message" }

function Find-BrowserExe {
    $pf = $env:ProgramFiles
    $pf86 = ${env:ProgramFiles(x86)}
    $candidates = @(
        (Join-Path $pf86 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $pf 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $pf86 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $pf 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

function ConvertTo-Ico {
    param([string]$PngPath, [string]$IcoPath)
    Add-Type -AssemblyName System.Drawing
    $bytes = [IO.File]::ReadAllBytes($PngPath)
    $ms = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter($ms)
    $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]1)          # ICONDIR
    $bw.Write([Byte]0); $bw.Write([Byte]0); $bw.Write([Byte]0); $bw.Write([Byte]0)  # 0 = 256px, 0 colors, reserved
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)                                # planes, bpp
    $bw.Write([UInt32]$bytes.Length); $bw.Write([UInt32]22)                    # size, offset
    $bw.Write($bytes)
    $bw.Flush()
    [IO.File]::WriteAllBytes($IcoPath, $ms.ToArray())
    $bw.Dispose(); $ms.Dispose()
}

function New-FallbackIconPng {
    param([string]$PngPath)
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 256, 256
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rect = New-Object System.Drawing.Rectangle 0, 0, 256, 256
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 112
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc(256 - $d, 0, $d, $d, 270, 90)
    $path.AddArc(256 - $d, 256 - $d, $d, $d, 0, 90)
    $path.AddArc(0, 256 - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(255,122,150,255), [System.Drawing.Color]::FromArgb(255,60,84,232), 45)
    $g.FillPath($brush, $path)
    $font = New-Object System.Drawing.Font('Segoe UI', 84, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString('DS', $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 0, 256, 256)), $sf)
    $bmp.Save($PngPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose(); $font.Dispose(); $brush.Dispose(); $path.Dispose()
}

# ---------------------------------------------------------------------------
# 1. Locate the harness installation to pin.
# ---------------------------------------------------------------------------
if (-not $SourceRoot) {
    $npxRoot = Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'
    if (Test-Path $npxRoot) {
        $dirs = Get-ChildItem $npxRoot -Directory | Sort-Object LastWriteTime -Descending
        foreach ($d in $dirs) {
            $manifest = Join-Path $d.FullName 'package.json'
            $binJs = Join-Path $d.FullName 'node_modules\@deepseek-ai\dsh\lib\bin.js'
            if ((Test-Path $manifest) -and (Test-Path $binJs) -and ((Get-Content $manifest -Raw) -like '*@deepseek-ai/dsh*')) {
                $SourceRoot = $d.FullName
                break
            }
        }
    }
}
if (-not $SourceRoot -or -not (Test-Path (Join-Path $SourceRoot 'node_modules\@deepseek-ai\dsh\lib\bin.js'))) {
    throw "Harness source not found. Install it once with: npx -y @deepseek-ai/dsh web  (then Ctrl+C to exit), and re-run this script. Or pass -SourceRoot <dir>."
}
Write-Step "Harness source: $SourceRoot"

# ---------------------------------------------------------------------------
# 2. Copy the harness into the install directory (pinned; no npx-cache tie).
# ---------------------------------------------------------------------------
$appDir = Join-Path $InstallDir 'app'
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Write-Step "Copying harness to $appDir (this may take a minute)..."
$null = robocopy $SourceRoot $appDir /MIR /NFL /NDL /NJH /NJS /NP /R:2 /W:2
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }

$binJs = Join-Path $appDir 'node_modules\@deepseek-ai\dsh\lib\bin.js'
if (-not (Test-Path $binJs)) { throw "Pinned copy is incomplete: $binJs missing" }

# ---------------------------------------------------------------------------
# 3. Copy this installer and the launcher scripts into the install directory.
# ---------------------------------------------------------------------------
foreach ($f in @('Launch.ps1', 'Stop.ps1', 'Uninstall.ps1')) {
    Copy-Item -Force (Join-Path $ScriptDir $f) (Join-Path $InstallDir $f)
}
Copy-Item -Force $PSCommandPath (Join-Path $InstallDir 'Reinstall.ps1')
if (Test-Path (Join-Path $ScriptDir 'README.md')) {
    Copy-Item -Force (Join-Path $ScriptDir 'README.md') (Join-Path $InstallDir 'README.md')
}

# ---------------------------------------------------------------------------
# 4. Smoke-test the pinned copy (compose the web profile, no server started).
# ---------------------------------------------------------------------------
$node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $node) { $node = Join-Path $env:ProgramFiles 'nodejs\node.exe' }
if (-not $node -or -not (Test-Path $node)) { throw 'Node.js not found. Install it from https://nodejs.org first.' }

$smokeOut = Join-Path $env:TEMP 'dsh-desktop-smoke.txt'
& $node $binJs web --dump-config *> $smokeOut
if ($LASTEXITCODE -ne 0) {
    $tail = ''
    if (Test-Path $smokeOut) { $tail = (Get-Content $smokeOut -Tail 5) -join "`n" }
    throw "Smoke test failed (exit $LASTEXITCODE):`n$tail"
}
Write-Step 'Pinned copy smoke test passed'

# ---------------------------------------------------------------------------
# 5. Generate the desktop icon.
# ---------------------------------------------------------------------------
$icoPath = Join-Path $InstallDir 'DSH.ico'
if (-not $SkipIcon) {
    $pngPath = Join-Path $InstallDir 'DSH-icon-256.png'
    $madePng = $false
    $favicon = Join-Path $appDir 'node_modules\@deepseek-ai\dsh-web-frontend\dist\favicon.svg'
    $browser = Find-BrowserExe
    if ($browser -and (Test-Path $favicon)) {
        $svgText = (Get-Content $favicon -Raw) -replace '<path id="path"', '<path id="path" fill="#ffffff"'
        $html = @"
<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;width:256px;height:256px;overflow:hidden;background:transparent}
.tile{width:256px;height:256px;border-radius:56px;background:linear-gradient(135deg,#7a96ff 0%,#4d6bfe 55%,#3c54e8 100%);display:flex;align-items:center;justify-content:center}
.tile svg{width:170px;height:170px;display:block}
</style></head><body><div class="tile">$svgText</div></body></html>
"@
        $htmlFile = Join-Path $env:TEMP 'dsh-desktop-icon.html'
        [IO.File]::WriteAllText($htmlFile, $html, [Text.Encoding]::UTF8)
        $fileUrl = 'file:///' + ($htmlFile -replace '\\', '/')
        try {
            & $browser '--headless=new' '--disable-gpu' '--hide-scrollbars' '--force-device-scale-factor=1' '--default-background-color=00000000' '--window-size=256,256' "--screenshot=$pngPath" $fileUrl | Out-Null
            Start-Sleep -Milliseconds 500
            if (Test-Path $pngPath) { $madePng = $true }
        } catch { }
    }
    if (-not $madePng) {
        Write-Host '[!] Browser-based icon rendering skipped; using built-in fallback icon.'
        New-FallbackIconPng $pngPath
        $madePng = Test-Path $pngPath
    }
    if ($madePng) {
        Add-Type -AssemblyName System.Drawing
        $bmp = [System.Drawing.Bitmap]::FromFile($pngPath)
        $corner = $bmp.GetPixel(2, 2)
        if ($corner.A -ne 0) {
            # Corners are not transparent: mask everything outside the rounded rect.
            for ($y = 0; $y -lt 256; $y++) {
                for ($x = 0; $x -lt 256; $x++) {
                    if (($x -lt 56 -or $x -gt 199) -and ($y -lt 56 -or $y -gt 199)) {
                        $dx = 56 - $x; if ($x -gt 199) { $dx = $x - 199 }
                        $dy = 56 - $y; if ($y -gt 199) { $dy = $y - 199 }
                        if (($dx * $dx + $dy * $dy) -gt 3136) { $bmp.SetPixel($x, $y, [System.Drawing.Color]::Transparent) }
                    }
                }
            }
            $bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        $bmp.Dispose()
        ConvertTo-Ico $pngPath $icoPath
        Write-Step "Icon generated: $icoPath"
    } else {
        Write-Host '[!] Icon generation failed; shortcuts will use the default icon.'
    }
}

# ---------------------------------------------------------------------------
# 6. Create Desktop and Start Menu shortcuts.
# ---------------------------------------------------------------------------
$ws = New-Object -ComObject WScript.Shell
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$launchArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $InstallDir 'Launch.ps1') + '"'
$stopArgs   = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $InstallDir 'Stop.ps1') + '"'

function New-AppShortcut {
    param([string]$Folder, [string]$Name, [string]$Arguments)
    $lnk = $ws.CreateShortcut((Join-Path $Folder $Name))
    $lnk.TargetPath = $psExe
    $lnk.Arguments = $Arguments
    if (Test-Path (Join-Path $InstallDir 'DSH.ico')) { $lnk.IconLocation = (Join-Path $InstallDir 'DSH.ico') + ',0' }
    $lnk.WorkingDirectory = $InstallDir
    $lnk.Description = 'DeepSeek Harness'
    $lnk.Save()
}

$desktopFolder  = [Environment]::GetFolderPath('Desktop')
$programsFolder = [Environment]::GetFolderPath('Programs')
New-AppShortcut $desktopFolder 'DeepSeek Harness.lnk' $launchArgs
New-AppShortcut $programsFolder 'DeepSeek Harness.lnk' $launchArgs
New-AppShortcut $programsFolder 'Stop DeepSeek Harness.lnk' $stopArgs

Write-Host ''
Write-Host '=== DeepSeek Harness desktop app installed ==='
Write-Host "Install dir : $InstallDir"
Write-Host "Desktop icon: $desktopFolder\DeepSeek Harness.lnk"
Write-Host 'Double-click the desktop icon to start. Closing the app window stops the service it started.'
Write-Host 'Start Menu also has "Stop DeepSeek Harness". Re-run this script any time to update.'
