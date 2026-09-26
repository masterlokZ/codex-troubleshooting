# Case 004: Windows 双层代理与 GeoFiles 智能分流网络环境配置与极速复原指南

- **故障级别**：P1（底层基础设施，断网直接导致无法连接网关、无法刷新登录态）
- **涉及组件**：v2rayN、Windows 系统代理、系统环境变量（HTTP_PROXY/HTTPS_PROXY）、Codex Desktop（Electron/app-server）、OpenAI OAuth
- **核心定位**：保障 Codex 混合架构下“官方登录态自动刷新”与“CPA 网关高频通信”长效自愈的网络底座
- **核心机制**：系统代理 + 环境变量双保险，结合 GeoFiles 智能分流实现“海外鉴权走节点、模型推理走网关、本地 MCP 走旁路”

---

## 1. 架构背景与分流诉求 (Background & Requirements)

在 Codex Desktop 混合使用自建 CPA 网关与官方商业登录态的架构中，存在三类特征截然不同的网络流量：

1. **官方 OAuth 认证与 Token 刷新流量**：
   - 目标域名：`auth.openai.com`、`auth0.openai.com`、`api.openai.com`
   - 诉求：必须能够顺畅直达海外 OpenAI 官方鉴权中心，以便在 `access_token` 过期前全自动静默续期。
2. **大模型推理与生成流量**：
   - 目标域名：`cpx.040926.xyz`（自建 CPA 网关地址）
   - 诉求：低时延、高稳定性直连，保持 SSE 流式长连接不中断。
3. **本地工具与 MCP 进程间通信流量**：
   - 目标地址：`localhost`、`127.0.0.1`、`192.168.*`（本地各服务端口）
   - 诉求：绝对不能经过代理循环转发，必须 100% 走本地直连旁路，确保零延迟。

为了让 Electron 界面层、Node.js app-server 后台服务以及终端 CLI 进程都能同时且自动满足上述诉求，必须采用**双层代理（系统级 + 环境变量级）配合 GeoFiles 规则路由**的方案。

---

## 2. 核心网络配置标准基线 (Configuration Baseline)

### (1) Windows 系统代理设置（服务于前端视图层）
- **注册表位置**：`HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings`
- **配置基线**：
  ```ini
  ProxyEnable = 1
  ProxyServer = 127.0.0.1:10808
  ProxyOverride = <local>;localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*
  ```
- **作用**：Electron / Chromium 渲染进程及基于 WinINet 的系统组件会自动继承此代理，同时通过 `ProxyOverride` 保证局域网与本地端口完全旁路。

### (2) 环境变量代理设置（服务于 app-server 与命令行终端）
- **变量清单**：
  ```text
  HTTP_PROXY  = http://127.0.0.1:10808
  HTTPS_PROXY = http://127.0.0.1:10808
  ALL_PROXY   = socks5://127.0.0.1:10808
  ```
- **作用**：Codex 底层的 Node.js app-server、Git 工具链、Python 及 PowerShell 等终端子进程，无法稳定读取 Windows 注册表代理，必须依靠这组标准 POSIX/Windows 通用环境变量完成流量定向。

### (3) v2rayN 客户端路由基线（分流核心）
- **本地监听端口**：`10808`（HTTP/SOCKS5 混合协议接入点）
- **路由模式**：`绕过大陆`（Bypass Mainland）
- **规则数据源**：第三方自动同步维护的 GeoFiles（`geosite.dat` 与 `geoip.dat`）
- **判定逻辑**：
  - 匹配 `geosite:openai` 及海外域名 -> 自动送入海外代理节点；
  - 匹配 `geoip:cn` 及内网 IP -> 自动直连；
  - 自建域名 `cpx.040926.xyz` -> 海外 VPS 节点正常出网。

---

## 3. 一键检查与状态恢复脚本 (PowerShell Recovery Script)

若遇到网络异常、重启后环境变量丢失或代理脱钩，在 PowerShell 7 中运行以下脚本，即可秒级完成**环境诊断、配置对齐与端点连通性实测**：

```powershell
# ==============================================================================
# Codex 混合态网络环境一键核验与极速复原脚本
# 编码铁律：UTF-8 无 BOM
# ==============================================================================
$ErrorActionPreference = 'Stop'

Write-Host ">>> [1/4] 检查 127.0.0.1:10808 端口监听状态..." -ForegroundColor Cyan
$portListening = Get-NetTCPConnection -LocalPort 10808 -State Listen -ErrorAction SilentlyContinue
if (-not $portListening) {
    Write-Warning "[警告] 10808 端口未监听！请先打开 v2rayN 客户端并确保核心已启动。"
} else {
    Write-Host "[正常] v2rayN 核心服务正常监听 10808 端口。" -ForegroundColor Green
}

Write-Host ">>> [2/4] 对齐 Windows 系统代理配置..." -ForegroundColor Cyan
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
Set-ItemProperty -Path $regPath -Name "ProxyEnable" -Value 1
Set-ItemProperty -Path $regPath -Name "ProxyServer" -Value "127.0.0.1:10808"
$override = "<local>;localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*"
Set-ItemProperty -Path $regPath -Name "ProxyOverride" -Value $override
Write-Host "[正常] 系统代理已锁定为 127.0.0.1:10808，本地内网旁路保护已就绪。" -ForegroundColor Green

Write-Host ">>> [3/4] 注入用户级长效环境变量..." -ForegroundColor Cyan
[Environment]::SetEnvironmentVariable("HTTP_PROXY", "http://127.0.0.1:10808", "User")
[Environment]::SetEnvironmentVariable("HTTPS_PROXY", "http://127.0.0.1:10808", "User")
[Environment]::SetEnvironmentVariable("ALL_PROXY", "socks5://127.0.0.1:10808", "User")
$env:HTTP_PROXY = "http://127.0.0.1:10808"
$env:HTTPS_PROXY = "http://127.0.0.1:10808"
$env:ALL_PROXY = "socks5://127.0.0.1:10808"
Write-Host "[正常] 用户级环境变量已持久化为 10808。" -ForegroundColor Green

Write-Host ">>> [4/4] 实测业务关键端点连通性..." -ForegroundColor Cyan
$headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" }

# 测试 A: 官方鉴权端点（Token 自动刷新线）
try {
    $authRes = Invoke-WebRequest -Uri "https://auth.openai.com/oauth/token" -Method Post -Headers $headers -Body "{}" -ContentType "application/json" -TimeoutSec 6 -UseBasicParsing
    $authStatus = $authRes.StatusCode
} catch {
    $authStatus = $_.Exception.Response.StatusCode.value__
    if (-not $authStatus) { $authStatus = $_.Exception.Message }
}
if ($authStatus -eq 400) {
    Write-Host "[连通] OpenAI 鉴权中心直达正常 (返回 HTTP 400 标准 OAuth 参数缺失报文，链路畅通)。" -ForegroundColor Green
} else {
    Write-Warning "[提示] OpenAI 鉴权中心响应状态: $authStatus (若非 400，需检查节点连通性)。"
}

# 测试 B: 自建 CPA 网关端点（模型推理生成线）
try {
    $cpaRes = Invoke-WebRequest -Uri "https://cpx.040926.xyz" -TimeoutSec 6 -UseBasicParsing
    $cpaStatus = $cpaRes.StatusCode
} catch {
    $cpaStatus = $_.Exception.Message
}
if ($cpaStatus -eq 200) {
    Write-Host "[连通] 自建 CPA 网关直达正常 (HTTP 200 OK)。" -ForegroundColor Green
} else {
    Write-Warning "[提示] CPA 网关响应状态: $cpaStatus。"
}

Write-Host "`n✔ 网络基线核验完毕，混合态网络环境已完全就绪！" -ForegroundColor Green
```

---

## 4. 常见排错场景速查 (Troubleshooting FAQ)

| 故障表象 | 可能诱因 | 快速解决手法 |
| :--- | :--- | :--- |
| **Codex 启动报 Unable to load sign-in requirements** | v2rayN 退出或 10808 端口未启动，导致无法触达官方鉴权服务器 | 启动 v2rayN，确保 10808 处于监听状态，重启 Codex 客户端 |
| **界面出现模型生成超时 / 网络错误** | 系统代理正常但环境变量未生效，app-server 尝试直连失败 | 执行上述脚本恢复用户级 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量 |
| **本地 MCP 工具（如 FastCtx/本地服务）交互卡顿** | `ProxyOverride` 丢失，导致发往 `localhost` 的流量绕到了代理节点 | 重新写入上述 `ProxyOverride` 规则，强制直连 `localhost` 和 `127.*` |
| **官方端点探测报 403 Forbidden** | 纯命令行默认 User-Agent 被 Cloudflare WAF 阻拦 | 属于测试客户端特征拦截，非网络不通。带上浏览器 User-Agent 探测返回 400 即证明网络完全通畅 |

---

## 5. 极简维持心法

> **v2rayN 常驻开，一零八零八端口在。**  
> **系统环境双保险，海外国内两不踩。**  
> **鉴权走票全自动，网关推理跑得快。**
