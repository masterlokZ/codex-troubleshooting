# Case 002: Windows 环境下执行 Git 触网命令被 GCM 劫持弹出 GUI 对话框卡死

- **故障级别**：P1（阻塞自动化流程、唤起桌面弹窗破坏用户体验）
- **涉及组件**：Git for Windows、Git Credential Manager (GCM)、PowerShell / CLI 执行环境、GitHub 交互
- **典型表象**：配置了 `$env:GIT_TERMINAL_PROMPT='0'` 与 `$env:GIT_ASKPASS=''`，执行触网命令控制台依然阻塞 8 秒以上，并在 Windows 桌面强行弹出 GitHub 凭证管理器独立窗口，超时报错 `fatal: User cancelled dialog.`
- **真实根因**：Git for Windows 默认配置 `credential.helper = manager`，GCM 是独立的 Win32 GUI 外部子进程，不接管终端 stdin；单纯屏蔽终端提示环境变量无法阻止外部 GUI 弹窗进程的唤起

---

## 1. 故障现象与混淆表象 (Symptoms & Misleading Signals)

在自动化脚本、CI/CD Agent、编码智能体（如 Codex Desktop / CLI）或无交互式 PowerShell 终端中执行 Git 触网命令（如 `git push`、`git push --dry-run`、`git fetch`、`git ls-remote`）时，出现严重的交互阻塞与弹窗劫持现象：

### 现场执行时序与输出
即使前置显式设置了阻止终端提示的环境变量：
```powershell
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_ASKPASS = ''
git push origin feature-branch --dry-run
```

控制台并未如预期在无凭据时立即失败退出，而是出现：
1. **控制台严重阻塞**：执行卡住 8~30 秒以上，毫无任何输出流输出；
2. **桌面焦点强行劫持**：Windows 桌面突然弹出 `git-credential-manager.exe` 的 Win32/WPF 独立登录窗口（要求输入 GitHub Token、OAuth 浏览器授权或设备码确认）；
3. **流程彻底中断**：
   - 若用户在桌面点击“取消”或关闭弹窗，控制台抛出：
     ```text
     fatal: User cancelled dialog.
     fatal: could not read Username for 'https://github.com': terminal prompts disabled
     ```
   - 若处于无人工值守的后台任务，控制台将持续挂起直到超时强杀，严重破坏端到端自动化流程与用户交互体验。

### 极具误导性的混淆表象
- **直观误区一**：“以为设置了 `GIT_TERMINAL_PROMPT=0` 就能全局静默无交互”。
  - 开发者常误以为 Git 的所有凭据交互都遵循 `GIT_TERMINAL_PROMPT`，忽视了 Windows 上 GCM 作为外部独立 GUI 进程的特殊机制。
- **直观误区二**：“以为设置了 `GIT_ASKPASS=''` 就能阻断外部程序唤起”。
  - `GIT_ASKPASS` 仅在 Git 自身需要调用密码输入助手程序时被触发，但当 `credential.helper` 被配置时，Git 优先把凭证获取工作委托给 Helper 处理，而 GCM 有自己的一套 UI 唤起逻辑。

---

## 2. 根因深度剖析 (Root Cause Analysis)

### (1) Windows Git 默认的 `credential.helper = manager` 机制
在通过官方安装包安装 Git for Windows 时，默认且推荐勾选的凭据助手为 **Git Credential Manager (GCM)**。Git 系统级配置（`git config --system --show-origin`）或全局配置中会自动注入：
```ini
[credential]
    helper = manager
```
（在较新版本中可能标识为 `manager` 或 `manager-core`，对应 `git-credential-manager.exe`）。

当 Git 执行任何涉及远程 HTTP/HTTPS 鉴权的网络操作（Fetch/Push/Pull/Clone/ls-remote）时，若本地当前未缓存有效凭据，Git 会按照配置启动该 Helper 请求凭证。

### (2) Win32 独立子进程与终端 stdin 解耦
这是环境变量静默方案失效的底层本质原因：
1. **`git-credential-manager.exe` 是一个完全独立的 Win32 GUI 应用程序**（基于 .NET / WPF 或 Win32 API 构建），拥有自己的消息循环与窗口句柄；
2. **不接管与不依赖终端标准输入（stdin）**：
   - `$env:GIT_TERMINAL_PROMPT = '0'` 的作用边界是：**通知 Git 核心（git.exe）在缺少凭证时不要尝试在控制台终端控制流中打印交互式提示符（如 `Username for 'https://github.com': `）向 stdin 读取字符**。
   - `$env:GIT_ASKPASS = ''` 的作用边界是：**清空 Git 默认的回调询问程序**。
   - 但是，Git 依然会按照凭据助手机制先执行 `git credential fill`，进而启动子进程 `git-credential-manager.exe get`。
3. **GCM 默认行为判定**：
   - GCM 发现当前未在无头服务（headless service / CI mode）受限环境下，且拥有可用的 Windows Desktop Window Station（WinSta0），便会自动决定拉起原生的 GUI 登录窗口等待人类点击；
   - 在 GUI 对话框存活期间，`git.exe` 处于阻塞等待子进程退出的状态；
   - 只有在窗口被关闭（返回取消错误码）后，GCM 退出，Git 才接收到凭据失败，继而输出 `fatal: User cancelled dialog.`，随后再触发 `fatal: could not read Username...: terminal prompts disabled`。

---

## 3. 标准规避与解决方案 (Fix & Prevention)

针对此类问题，必须建立阶梯式防御：**网络只读/写入优先走 API，本地兜底彻底拔除 Helper**。

### 方案一（终极根治）：全面改用 GitHub REST API（API 优先铁律）

在自动化 Agent、脚本或开发工具中，**彻底脱离原生 `git` 触网命令**。凡是涉及远程状态查询（比对分支、查看远程 Commit、检查 PR）或代码推送，100% 通过环境变量 `GITHUB_TOKEN` 直接调用 GitHub REST API。

#### 1. 远程状态查询（避免 `git fetch` / `git ls-remote`）
使用原生 HTTP 请求直接查询 GitHub API，耗时从数秒降低到毫秒级，且绝对无任何进程唤起与凭据弹窗风险：

```powershell
# PowerShell 7 示例：查询远程仓库分支最新提交 SHA
$headers = @{
    "Authorization" = "Bearer $env:GITHUB_TOKEN"
    "Accept"        = "application/vnd.github+json"
}
$repo = "owner/repo"
$branch = "main"
$response = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/$branch" -Headers $headers -Method Get
$latestSha = $response.sha
Write-Host "远程最新 Commit: $latestSha"
```

#### 2. 代码提交与推送（基于 GitHub REST / Git Data API）
对于自动化场景，使用 GitHub Git Database API（Blobs, Trees, Commits, Refs）或标准 API 直接创建提交并更新分支引用，全链路在 HTTP 传输层通过 Bearer Token 闭环完成。

---

### 方案二（本地只读静默）：强制附加 `-c credential.helper=""` 物理拔除系统凭据助手

如果某些特定只读分析或探针场景**必须**调用本地 `git` 命令行（例如读取远程引用 `git ls-remote`），必须显式在命令行参数中传入空配置，**在内存配置级别物理拔除全局与系统凭据助手**：

```powershell
# 本地只读安全探针执行范式
$env:GIT_TERMINAL_PROMPT = '0'
$env:GIT_ASKPASS = ''
git -c credential.helper="" ls-remote origin
```

#### 为什么必须是 `-c credential.helper=""`？
- Git 的命令行 `-c <name>=<value>` 参数具有最高优先级，能瞬间覆盖 System、Global 和 Local 配置文件中的 `helper = manager`。
- 将 `credential.helper` 设为空字符串 `""`，会彻底清空凭据助手链条。
- 当 Git 缺少认证信息时，由于凭据助手已被物理拔除，且 `GIT_TERMINAL_PROMPT=0` 阻止了终端提示，Git 会在 **0.1 秒内直接以非零状态码快速失败退出**，彻底断绝拉起任何 GUI 弹窗的可能！

---

## 4. 反模式禁忌与自动化流水线规范

| 场景 | 错误做法 (Anti-Pattern) | 正确规范 (Best Practice) |
| :--- | :--- | :--- |
| **远程分支比对 / PR 查询** | 使用 `git fetch` / `git remote update` | 使用 `GITHUB_TOKEN` 调用 GitHub REST API 查询 |
| **自动化检查推送** | 直接裸跑 `git push --dry-run` | API 校验优先；若不可避免，必加 `-c credential.helper=""` |
| **本地凭据屏蔽配置** | 仅配置 `$env:GIT_TERMINAL_PROMPT = '0'` | 强制叠加 `-c credential.helper=""` 物理阻断 GCM 进程 |
| **无凭据场景预期** | 期望弹窗让用户手动输入密码 | 自动化进程必须即时快速失败，杜绝破坏桌面交互 |

---

## 5. 总结口诀

> **触网命令莫裸跑，GCM 弹窗把人扰。**
> **远程状态调接口，Bearer 令牌最可靠。**
> **若需本地探针查，清空 Helper 拔插头。**
