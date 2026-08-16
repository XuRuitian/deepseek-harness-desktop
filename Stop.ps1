# Stop.ps1 - stop the desktop app's server and close its app window.
$ErrorActionPreference = 'SilentlyContinue'
$Root       = Split-Path -Parent $MyInvocation.MyCommand.Definition
$StateDir   = Join-Path $env:LOCALAPPDATA 'DSHDesktop'
$PidFile    = Join-Path $StateDir 'logs\server.pid'
$ProfileDir = Join-Path $StateDir 'edge-profile'

if (Test-Path $PidFile) {
    $value = Get-Content $PidFile | Select-Object -First 1
    $pidNum = 0
    if ($value -and [int]::TryParse($value.Trim(), [ref]$pidNum) -and $pidNum -gt 0) {
        $proc = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
        if ($proc) {
            $cmdline = (Get-CimInstance Win32_Process -Filter "ProcessId=$pidNum" -ErrorAction SilentlyContinue).CommandLine
            if ($cmdline -like '*app\node_modules\@deepseek-ai\dsh\lib\bin.js*') {
                Stop-Process -Id $pidNum -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and ($_.CommandLine -like "*$ProfileDir*") } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
