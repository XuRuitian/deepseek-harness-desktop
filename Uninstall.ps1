# Uninstall.ps1 - remove the desktop app. User data under ~/.dsh is kept.
$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$confirm = Read-Host 'Remove the DeepSeek Harness desktop app? Your data under ~/.dsh is kept. Type YES to confirm'
if ($confirm -ne 'YES') { Write-Host 'Cancelled.'; exit 0 }

& (Join-Path $Root 'Stop.ps1')

$desktop  = [Environment]::GetFolderPath('Desktop')
$programs = [Environment]::GetFolderPath('Programs')
foreach ($f in @((Join-Path $desktop 'DeepSeek Harness.lnk'),
                 (Join-Path $programs 'DeepSeek Harness.lnk'),
                 (Join-Path $programs 'Stop DeepSeek Harness.lnk'))) {
    Remove-Item $f -Force -ErrorAction SilentlyContinue
}

# Delete the install directory after this script exits.
Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/c ping -n 2 127.0.0.1 >nul & rmdir /s /q `"$Root`"" -WindowStyle Hidden
Write-Host 'DeepSeek Harness desktop app removed. User data in ~/.dsh was kept.'
