# publish.ps1 - publish source + release exe to GitHub (API-only, network-tolerant).
# Token is read from build\.github-token (git-ignored); never commit it.
# Safe to re-run: file updates and release/asset operations are idempotent.
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Log = Join-Path $Root 'build\publish.log'
function Log { param([string]$M) $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $M; Add-Content -Path $Log -Value $line -Encoding UTF8; Write-Host $line }
function Read-Utf8 { param([string]$Path) if (Test-Path $Path) { return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) } return '' }
function Write-Utf8 { param([string]$Path, [string]$Text) [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false)) }

New-Item -ItemType Directory -Force -Path (Join-Path $Root 'build') | Out-Null
Set-Content -Path $Log -Value '=== publish start ===' -Encoding UTF8

$TokenFile = Join-Path $Root 'build\.github-token'
if (-not (Test-Path $TokenFile)) {
    $cred = "protocol=https`nhost=github.com`n" | git credential fill 2>$null
    $token = ($cred | Select-String '^password=').ToString().Substring(9)
    if ($token) { Write-Utf8 $TokenFile $token }
} else {
    $token = [IO.File]::ReadAllText($TokenFile).Trim()
}
if (-not $token) { Log 'No GitHub token (build\.github-token missing and credential fill failed)'; exit 1 }

$Owner   = 'XuRuitian'
$Repo    = 'deepseek-harness-desktop'
$Api     = "https://api.github.com/repos/$Owner/$Repo"
$AuthH   = "Authorization: Bearer $token"
$UaH     = 'User-Agent: dsh-desktop-builder'
$Version = '0.1.0-rc.6'

function Api {
    param([string]$Method, [string]$Url, [string]$JsonFile, [string]$OutFile)
    $args = @('-sS', '-m', '180', '--retry', '3', '--retry-delay', '2', '-X', $Method, '-H', $AuthH, '-H', $UaH)
    if ($JsonFile) { $args += @('-H', 'Content-Type: application/json', '--data-binary', "@$JsonFile") }
    $args += $Url
    if ($OutFile) { & curl.exe @args -o $OutFile 2>$null } else { & curl.exe @args 2>$null }
}

# ---------------------------------------------------------------------------
# 1. Sync source files onto main via the Contents API (update in place).
# ---------------------------------------------------------------------------
$files = @('.gitignore','LICENSE','README.md','Install.ps1','Launch.ps1','Stop.ps1','Uninstall.ps1','installer/DSHSetup.iss','publish.ps1')
foreach ($f in $files) {
    $p = Join-Path $Root $f
    if (-not (Test-Path $p)) { Log "SKIP (missing): $f"; continue }
    $apiPath = ((($f -replace '\\','/') -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    $metaFile = "$env:TEMP\dsh-meta.json"
    Api 'GET' "$Api/contents/$apiPath`?ref=main" $null $metaFile
    $meta = Read-Utf8 $metaFile
    $sha = $null
    if ($meta -match '"sha"\s*:\s*"([0-9a-f]{40})"') { $sha = $Matches[1] }
    $payload = @{
        message = 'DeepSeek Harness desktop launcher + Inno Setup installer'
        content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($p))
        branch  = 'main'
    }
    if ($sha) { $payload.sha = $sha }
    $jsonFile = "$env:TEMP\dsh-content.json"
    Write-Utf8 $jsonFile ($payload | ConvertTo-Json)
    $outFile = "$env:TEMP\dsh-content-resp.json"
    Api 'PUT' "$Api/contents/$apiPath" $jsonFile $outFile
    $body = Read-Utf8 $outFile
    if ($body -match '"sha"\s*:\s*"([0-9a-f]+)"') { Log "file ok: $f" } else { Log "FILE FAILED for $f : $body" }
}
Log '=== source publish done ==='

# ---------------------------------------------------------------------------
# 2. Create (or update) the release, then upload the setup exe.
# ---------------------------------------------------------------------------
$exePath = Join-Path $Root "dist\DeepSeekHarness-Setup-$Version.exe"
if (-not (Test-Path $exePath)) { Log "EXE MISSING: $exePath"; exit 1 }
$hash = (Get-FileHash $exePath -Algorithm SHA256).Hash.ToLower()

$relBody = @(
    'DeepSeek Harness 的 Windows 桌面版一键安装包：双击运行，向导中可选择安装路径，安装后桌面与开始菜单出现应用图标。',
    '',
    '## 功能',
    '- 双击图标即用：自动启动服务 + 弹出应用窗口（无需手动开终端/浏览器）',
    '- 已有 harness 运行时自动复用，不重复启动；关闭窗口自动回收桌面版启动的服务',
    '- 数据沿用 ~/.dsh，与命令行版共享会话与配置',
    '- 开始菜单附带 Stop DeepSeek Harness 快捷方式',
    '',
    '## 使用前提',
    '- 需要已安装 Node.js（https://nodejs.org），安装向导会检测并提示',
    '',
    '## 校验',
    ("- SHA256: " + $hash),
    '',
    '源码见仓库 main 分支，构建方式见 README。'
) -join "`n"

$jsonFile = "$env:TEMP\dsh-release.json"
Write-Utf8 $jsonFile (@{
    tag_name = "v$Version"
    target_commitish = 'main'
    name = "DeepSeek Harness Desktop v$Version"
    body = $relBody
    draft = $false
    prerelease = $true
} | ConvertTo-Json)

$checkFile = "$env:TEMP\dsh-rel-check.json"
Api 'GET' "$Api/releases/tags/v$Version" $null $checkFile
$existing = Read-Utf8 $checkFile
$outFile = "$env:TEMP\dsh-release-resp.json"
if ($existing -match '"upload_url"') {
    Log 'release exists; updating body'
    $relId = [regex]::Match($existing, '"id"\s*:\s*(\d+)').Groups[1].Value
    Api 'PATCH' "$Api/releases/$relId" $jsonFile $outFile
} else {
    Log 'creating release'
    Api 'POST' "$Api/releases" $jsonFile $outFile
}
$relResp = Read-Utf8 $outFile
if ($relResp -notmatch '"upload_url"') { Log "RELEASE FAILED: $relResp"; exit 1 }
$rel = $relResp | ConvertFrom-Json
Log ("release: " + $rel.html_url)

# Upload the asset (skips if it is already attached).
$existingAssets = $rel.assets | ForEach-Object { $_.name }
if ($existingAssets -contains "DeepSeekHarness-Setup-$Version.exe") {
    Log 'asset already uploaded; skipping'
} else {
    $uploadUrl = ($rel.upload_url -replace '\{[^}]*\}', '') + "?name=DeepSeekHarness-Setup-$Version.exe"
    $outFile = "$env:TEMP\dsh-asset-resp.json"
    Log 'uploading asset (32MB)...'
    & curl.exe -sS -m 2700 --retry 3 --retry-delay 5 -X POST -H $AuthH -H $UaH -H 'Content-Type: application/octet-stream' --data-binary "@$exePath" -o $outFile $uploadUrl 2>$null
    $assetBody = Read-Utf8 $outFile
    if ($assetBody -match '"browser_download_url"') {
        $asset = $assetBody | ConvertFrom-Json
        Log ("asset uploaded: " + $asset.browser_download_url)
    } else {
        Log "ASSET FAILED: $assetBody"
        exit 1
    }
}
Log '=== publish complete ==='
