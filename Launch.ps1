# Launch.ps1 - DeepSeek Harness desktop launcher.
# Starts the harness web server (or reuses an already-running one) and opens it
# in a dedicated desktop app window (Edge/Chrome app mode). When that window is
# closed, the server is stopped only if this launcher started it.
param(
    [int]$Port = 3080,
    [switch]$NoWindow
)

$ErrorActionPreference = 'Stop'
$Root        = Split-Path -Parent $MyInvocation.MyCommand.Definition
$AppBin      = Join-Path $Root 'app\node_modules\@deepseek-ai\dsh\lib\bin.js'
$StateDir    = Join-Path $env:LOCALAPPDATA 'DSHDesktop'
$LogDir      = Join-Path $StateDir 'logs'
$LauncherLog = Join-Path $LogDir 'launcher.log'
$PidFile     = Join-Path $LogDir 'server.pid'
$ProfileDir  = Join-Path $StateDir 'edge-profile'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log {
    param([string]$Message)
    try {
        Add-Content -Path $LauncherLog -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding ASCII
    } catch { }
}

function Show-Error {
    param([string]$Message)
    Write-Log "ERROR: $Message"
    try {
        $sh = New-Object -ComObject WScript.Shell
        $null = $sh.Popup($Message, 0, 'DeepSeek Harness', 48)
    } catch { }
}

function Find-NodeExe {
    $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $pf86 = ${env:ProgramFiles(x86)}
    foreach ($c in @((Join-Path $env:ProgramFiles 'nodejs\node.exe'), (Join-Path $pf86 'nodejs\node.exe'))) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Test-PortOpen {
    param([int]$Port)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(600)) { return $false }
        try { $client.EndConnect($async); return $true } catch { return $false }
    } catch { return $false }
    finally { $client.Close() }
}

function Test-HarnessReady {
    param([string]$Url, [int]$TimeoutMs = 2500)
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Timeout = $TimeoutMs
        $req.ReadWriteTimeout = $TimeoutMs
        $req.Method = 'GET'
        $req.UserAgent = 'DSHDesktop/1.0'
        $resp = $req.GetResponse()
        try {
            if ($resp.StatusCode -ne [System.Net.HttpStatusCode]::OK) { return $false }
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $body = $reader.ReadToEnd()
            return ($body -like '*DeepSeek Harness*')
        } finally { $resp.Close() }
    } catch { return $false }
}

function Start-DshServer {
    param([string]$NodeExe, [string]$Bin, [int]$Port)
    $outLog = Join-Path $LogDir 'server.out.log'
    $errLog = Join-Path $LogDir 'server.err.log'
    foreach ($f in @($outLog, $errLog)) {
        if (Test-Path "$f.prev") { Remove-Item "$f.prev" -Force -ErrorAction SilentlyContinue }
        if (Test-Path $f) { Move-Item -Force $f "$f.prev" }
    }
    $argLine = '"{0}" web --port {1}' -f $Bin, $Port
    Write-Log "starting server: $NodeExe $argLine"
    $proc = Start-Process -FilePath $NodeExe -ArgumentList $argLine -WorkingDirectory $env:USERPROFILE -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
    return $proc
}

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

function Wait-BrowserMainExit {
    param([string]$ExeName, [string]$ProfilePath, [int]$TimeoutSec = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $foundPid = $null
    while ((Get-Date) -lt $deadline) {
        $proc = Get-CimInstance Win32_Process -Filter "Name='$ExeName'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and ($_.CommandLine -like "*$ProfilePath*") -and ($_.CommandLine -notlike '*--type=*') } |
            Sort-Object ProcessId | Select-Object -First 1
        if ($proc) { $foundPid = [int]$proc.ProcessId; break }
        Start-Sleep -Milliseconds 400
    }
    if ($foundPid) {
        Write-Log "browser main process $foundPid found; waiting for the app window to close"
        Wait-Process -Id $foundPid -ErrorAction SilentlyContinue
        return $true
    }
    Write-Log 'timed out waiting for the browser main process'
    return $false
}

Write-Log '=== launch ==='

if (-not (Test-Path $AppBin)) {
    Show-Error 'DeepSeek Harness app files are missing. Please re-run the installer (DeepSeekHarness-Setup.exe).'
    exit 1
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$node = Find-NodeExe
if (-not $node) {
    Show-Error 'Node.js was not found. Please install Node.js first (https://nodejs.org).'
    exit 1
}

# Clean a stale pid file (process gone, or not our server).
if (Test-Path $PidFile) {
    $oldPid = 0
    $raw = Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($raw) { $null = [int]::TryParse($raw.Trim(), [ref]$oldPid) }
    $stale = $true
    if ($oldPid -gt 0) {
        $cmdline = (Get-CimInstance Win32_Process -Filter "ProcessId=$oldPid" -ErrorAction SilentlyContinue).CommandLine
        if ($cmdline -like '*app\node_modules\@deepseek-ai\dsh\lib\bin.js*') { $stale = $false }
    }
    if ($stale) { Remove-Item $PidFile -Force -ErrorAction SilentlyContinue }
}

# Resolve the URL: reuse a running harness on the requested port, otherwise start one.
$startedByUs = $false
$serverProc = $null
$url = "http://127.0.0.1:$Port"

if (Test-PortOpen $Port) {
    if (Test-HarnessReady $url) {
        Write-Log "reusing existing harness at $url"
    } else {
        $freePort = 0
        for ($p = $Port + 1; $p -lt $Port + 25; $p++) {
            if (-not (Test-PortOpen $p)) { $freePort = $p; break }
        }
        if ($freePort -eq 0) {
            Show-Error "Port $Port is busy and no free port was found nearby."
            exit 1
        }
        $Port = $freePort
        $url = "http://127.0.0.1:$Port"
        $serverProc = Start-DshServer $node $AppBin $Port
        $startedByUs = $true
    }
} else {
    $serverProc = Start-DshServer $node $AppBin $Port
    $startedByUs = $true
}

if ($startedByUs) {
    [string]$serverProc.Id | Set-Content -Path $PidFile -Encoding ASCII
    $ready = $false
    for ($i = 0; $i -lt 100; $i++) {
        if (Test-HarnessReady $url 800) { $ready = $true; break }
        $serverProc.Refresh()
        if ($serverProc.HasExited) { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) {
        Write-Log "server did not become ready; see logs\server.err.log"
        Show-Error "The DeepSeek Harness server failed to start. See $LogDir\server.err.log"
        Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
    Write-Log "server ready on $url (pid $($serverProc.Id))"
}

if ($NoWindow) {
    Write-Log 'no-window mode: server left running'
    exit 0
}

$browser = Find-BrowserExe
if ($browser) {
    $exeName = Split-Path $browser -Leaf
    $argLine = '--app="{0}" --user-data-dir="{1}" --no-first-run --no-default-browser-check --disable-features=msEdgeFirstRunExperience --window-size=1440,900' -f $url, $ProfileDir
    Write-Log "opening app window: $browser $argLine"
    Start-Process -FilePath $browser -ArgumentList $argLine | Out-Null
    $null = Wait-BrowserMainExit $exeName $ProfileDir
} else {
    Write-Log 'no Edge/Chrome found; opening the default browser (server left running)'
    Start-Process $url | Out-Null
}

if ($startedByUs) {
    Write-Log 'app window closed; stopping the server this launcher started'
    Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}
Write-Log '=== exit ==='
