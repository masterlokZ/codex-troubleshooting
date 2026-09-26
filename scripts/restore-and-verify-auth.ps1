<#
.SYNOPSIS
    一键恢复与核验 Codex 官方登录态凭据（auth.json），并联动检查 CC Switch 保活状态。
.PARAMETER BackupPath
    自定义黄金备份路径，默认为 D:\codex-auth-backup\auth.json（备选 U:\codex-auth-backup\auth.json）。
#>
param(
    [string]$BackupPath = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=== Codex 官方登录态极速恢复与健康体检工具 ===" -ForegroundColor Cyan

# 1. 自动定位黄金备份
$candidates = @(
    $BackupPath,
    "D:\codex-auth-backup\auth.json",
    "U:\codex-auth-backup\auth.json"
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$sourceBackup = $null
foreach ($path in $candidates) {
    if (Test-Path -LiteralPath $path) {
        $sourceBackup = $path
        break
    }
}

if (-not $sourceBackup) {
    Write-Error "[致命错误] 未能在以下候选路径中找到官方 auth.json 黄金备份: ($($candidates -join ', '))"
    exit 1
}

Write-Host "[定位备份] 选用黄金凭据来源: $sourceBackup" -ForegroundColor Green

# 2. 目标路径准备
$targetDir = Join-Path $env:USERPROFILE ".codex"
$targetAuth = Join-Path $targetDir "auth.json"

if (-not (Test-Path -LiteralPath $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

# 3. 物理执行还原
Copy-Item -LiteralPath $sourceBackup -Destination $targetAuth -Force
Write-Host "[凭据还原] 已成功将 auth.json 写入: $targetAuth" -ForegroundColor Green

# 4. 哈希一致性校验
$srcHash = (Get-FileHash -LiteralPath $sourceBackup -Algorithm SHA256).Hash
$dstHash = (Get-FileHash -LiteralPath $targetAuth -Algorithm SHA256).Hash

if ($srcHash -eq $dstHash) {
    Write-Host "[哈希校验] SHA256 完全对齐: $dstHash" -ForegroundColor Green
} else {
    Write-Error "[校验失败] 源文件与目标文件哈希不一致！"
    exit 1
}

# 5. 解析并核验证书身份断言 (JWT Payload)
try {
    $rawJson = Get-Content -LiteralPath $targetAuth -Raw -Encoding utf8 | ConvertFrom-Json
    $idToken = $rawJson.tokens.id_token
    if ($idToken) {
        $parts = $idToken.Split(".")
        if ($parts.Length -ge 2) {
            $base64 = $parts[1].Replace("-", "+").Replace("_", "/")
            switch ($base64.Length % 4) {
                2 { $base64 += "==" }
                3 { $base64 += "=" }
            }
            $payloadBytes = [Convert]::FromBase64String($base64)
            $payloadText = [System.Text.Encoding]::UTF8.GetString($payloadBytes)
            $jwt = $payloadText | ConvertFrom-Json
            
            $planType = $jwt."https://api.openai.com/auth".chatgpt_plan_type
            $email = $jwt.email
            Write-Host "[身份断言] 账号邮箱: $email | 订阅类型: $planType" -ForegroundColor Cyan
        }
    }
} catch {
    Write-Warning "[提示] JWT 凭证解析略过: $($_.Exception.Message)"
}

# 6. 检查 CC Switch 保活开关防御体系
$ccSettingsPath = Join-Path $env:USERPROFILE ".cc-switch\settings.json"
if (Test-Path -LiteralPath $ccSettingsPath) {
    try {
        $ccSettings = Get-Content -LiteralPath $ccSettingsPath -Raw -Encoding utf8 | ConvertFrom-Json
        $preserved = $ccSettings.preserveCodexOfficialAuthOnSwitch
        if ($preserved -eq $true) {
            Write-Host "[防删免疫] CC Switch preserveCodexOfficialAuthOnSwitch = true (常驻免疫开启)" -ForegroundColor Green
        } else {
            Write-Warning "[高危警告] CC Switch preserveCodexOfficialAuthOnSwitch 处于关闭状态！"
            Write-Warning "下次切换第三方卡片时 auth.json 仍会被物理删除！"
            Write-Host "是否立即自动开启保活？(推荐直接开启)" -ForegroundColor Yellow
            $ccSettings.preserveCodexOfficialAuthOnSwitch = $true
            $newJson = $ccSettings | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($ccSettingsPath, $newJson, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "[自动修复] 已成功将 settings.json preserveCodexOfficialAuthOnSwitch 置为 true！" -ForegroundColor Green
        }
    } catch {
        Write-Warning "[防删检测] 无法读取 CC Switch 设置: $($_.Exception.Message)"
    }
}

Write-Host "=== 恢复完成！请重启 Codex Desktop 客户端即可看到左下角头像与登录态完全回归 ===" -ForegroundColor Green
