# publish.ps1 - publish source + release exe to GitHub (API-only, network-tolerant).
# Token is read from build\.github-token (git-ignored); never commit it.
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Log = Join-Path $Root 'build\publish.log'
function Log { param([string]$M) $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $M; Add-Content -Path $Log -Value $line -Encoding UTF8; Write-Host $line }

New-Item -ItemType Directory -Force -Path (Join-Path $Root 'build') | Out-Null
Set-Content -Path $Log -Value '=== publish start ===' -Encoding UTF8

$TokenFile = Join-Path $Root 'build\.github-token'
if (-not (Test-Path $TokenFile)) {
    $cred = "protocol=https`nhost=github.com`n" | git credential fill 2>$null
    $token = ($cred | Select-String '^password=').ToString().Substring(9)
    if ($token) { [IO.File]::WriteAllText($TokenFile, $token) }
} else {
    $token = [IO.File]::ReadAllText($TokenFile).Trim()
}
if (-not $token) { Log 'No GitHub token (build\.github-token missing and credential fill failed)'; exit 1 }

$Owner  = 'XuRuitian'
$Repo   = 'deepseek-harness-desktop'
$Api    = "https://api.github.com/repos/$Owner/$Repo"
$AuthH  = "Authorization: Bearer $token"
$UaH    = 'User-Agent: dsh-desktop-builder'
$Version = '0.1.0-rc.6'

function Api {
    param([string]$Method, [string]$Url, [string]$JsonFile, [string]$OutFile)
    $args = @('-sS', '-m', '180', '--retry', '3', '--retry-delay', '2', '-X', $Method, '-H', $AuthH, '-H', $UaH)
    if ($JsonFile) { $args += @('-H', 'Content-Type: application/json', '--data-binary', "@$JsonFile") }
    $args += $Url
    if ($OutFile) { & curl.exe @args -o $OutFile } else { & curl.exe @args }
}

# ---------------------------------------------------------------------------
# 1. Upload source files as commits on main (Contents API; works on empty repos).
# ---------------------------------------------------------------------------
$files = @('.gitignore','LICENSE','README.md','Install.ps1','Launch.ps1','Stop.ps1','Uninstall.ps1','installer/DSHSetup.iss','publish.ps1')
foreach ($f in $files) {
    $p = Join-Path $Root $f
    if (-not (Test-Path $p)) { Log "SKIP (missing): $f"; continue }
    $apiPath = ((($f -replace '\\','/') -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    $json = @{
        message = 'DeepSeek Harness desktop launcher + Inno Setup installer'
        content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($p))
        branch  = 'main'
    } | ConvertTo-Json
    $jsonFile = "$env:TEMP\dsh-content.json"; [IO.File]::WriteAllText($jsonFile, $json)
    $outFile = "$env:TEMP\dsh-content-resp.json"
    Api 'PUT' "$Api/contents/$apiPath" $jsonFile $outFile
    $body = Get-Content $outFile -Raw
    if ($body -match '"sha"\s*:\s*"([0-9a-f]+)"') { Log "file ok: $f" } else { Log "FILE FAILED for $f : $body" }
}
Log '=== source publish done ==='

# ---------------------------------------------------------------------------
# 2. Create a release and upload the setup exe.
# ---------------------------------------------------------------------------
$exePath = Join-Path $Root "dist\DeepSeekHarness-Setup-$Version.exe"
if (-not (Test-Path $exePath)) { Log "EXE MISSING: $exePath"; exit 1 }
$hash = (Get-FileHash $exePath -Algorithm SHA256).Hash.ToLower()

$relBody = @"
DeepSeek Harness 的 Windows 桌面版一键安装包：双击运行，向导中可选择安装路径，安装后桌面与开始菜单出现应用图标。

## 功能
- 双击图标即用：自动启动服务 + 弹出应用窗口（无需手动开终端/浏览器）
- 已有 harness 运行时自动复用，不重复启动；关闭窗口自动回收桌面版启动的服务
- 数据沿用 `~/.dsh`，与命令行版共享会话与配置
- 开始菜单附带 Stop DeepSeek Harness 快捷方式

## 使用前提
- 需要已安装 [Node.js](https://nodejs.org)（安装向导会检测并提示）

## 校验
- SHA256: `$hash`

源码见仓库 [main](../../tree/main) 分支。构建方式见 [README](../../blob/main/README.md)。
"@
$jsonFile = "$env:TEMP\dsh-release.json"
[IO.File]::WriteAllText($jsonFile, (@{
    tag_name = "v$Version"
    target_commitish = 'main'
    name = "DeepSeek Harness Desktop v$Version"
    body = $relBody
    draft = $false
    prerelease = $true
} | ConvertTo-Json))
$outFile = "$env:TEMP\dsh-release-resp.json"
Api 'POST' "$Api/releases" $jsonFile $outFile
$relBody = Get-Content $outFile -Raw
if ($relBody -notmatch '"upload_url"') { Log "RELEASE FAILED: $relBody"; exit 1 }
$rel = $relBody | ConvertFrom-Json
Log ("release created: " + $rel.html_url)

$uploadUrl = ($rel.upload_url -replace '\{[^}]*\}', '') + "?name=DeepSeekHarness-Setup-$Version.exe"
$outFile = "$env:TEMP\dsh-asset-resp.json"
Log 'uploading asset (32MB, may take a while)...'
& curl.exe -sS -m 2700 --retry 3 --retry-delay 5 -X POST -H $AuthH -H $UaH -H 'Content-Type: application/octet-stream' --data-binary "@$exePath" -o $outFile $uploadUrl
$assetBody = Get-Content $outFile -Raw
if ($assetBody -match '"browser_download_url"') {
    $asset = $assetBody | ConvertFrom-Json
    Log ("asset uploaded: " + $asset.browser_download_url)
} else {
    Log "ASSET FAILED: $assetBody"
    exit 1
}
Log '=== publish complete ==='
