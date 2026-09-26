# Case 005: Codex Desktop 版本升级路径失效与 CC Switch 多版本配置档案热备切换实战

- **故障级别**：P1（版本升级导致 CUA/电脑操控死链；以及 CC Switch 本地路由认知偏差）
- **涉及组件**：Codex Desktop（WindowsApps）、CUA Node 运行时（`@oai/sky`）、内嵌浏览器插件、CC Switch（配置切换器）、自建 CPA
- **核心定位**：解决客户端静默升级后绝对路径失效的平滑迁移问题，确立 CC Switch 作为“多版本热备切换档案库”的标准用法
- **实测验收标准**：通过 `@oai/sky` 调用 `sky.list_windows()` 成功探测桌面 11 个活动窗口并完成窗口状态捕获，Computer Use Overlay 正常响应

---

## 1. 现象与典型坑点 (Symptoms & Confusion)

### (1) WindowsApps 静默升级引发的“死链”隐患
当 Codex Desktop 自动升级（如从 `26.924.20706` 自动跨越至 `26.924.22138`）后：
1. 大模型对话推理仍然正常（因直连 CPA，与版本解耦）；
2. 但在调用 Computer Use（`@电脑`）或内嵌浏览器时，会突然报错不可用；
3. **排查事实**：安装程序在升级时**物理删除了旧版本的哈希目录**（如 `runtimes\cua_node\b35a...` 与 `bin\d235...`），使得 `config.toml` 中硬编码的 4 个段落共 7 处路径全部沦为无效死链（`Test-Path = False`）。

### (2) CC Switch “本地路由”的认知陷阱
在排错过程中，容易误以为必须将 Codex 的 `base_url` 改写为 CC Switch 的本地监听地址 `http://127.0.0.1:15721/v1`：
1. 改写后，Codex 发送的 `/responses` 请求遭遇 405 Method Not Allowed 或 400 Bad Request（`unknown provider for model`），导致通信直接崩塌；
2. **混淆根因**：混淆了 CC Switch 的“配置档案管理器”主功能与“本地反向代理”辅助功能。

---

## 2. 根因深度剖析 (Root Cause Analysis)

### (1) Codex 版本资源路径机制
Codex Desktop 升级后，资源存放规律如下：
- **CLI 二进制**：`AppData\Local\OpenAI\Codex\bin\<动态Hash>\codex.exe`（旧 Hash 物理清除，新 Hash 如 `faa963e871dd422c` 生效）；
- **CUA 运行时**：`AppData\Local\OpenAI\Codex\runtimes\cua_node\<动态Hash>\`（旧 Hash 物理清除，新 Hash 如 `b63ee7ee40c23b77` 生效）；
- **官方捆绑插件**：`.codex\plugins\cache\openai-bundled\browser\<新版本号>\` 与 `computer-use\<新版本号>\`。

### (2) CC Switch 底层真实架构审计
通过逆向分析 `cc-switch.exe` 二进制与实时数据库 `cc-switch.db`，确立核心机理：
1. **用量统计走日志分析，不走网络抓包**：
   CC Switch 内部运行 `session_usage_codex` 服务，自动读取 `C:\Users\Administrator\.codex\sessions\` 下的 `.jsonl` 本地文件。它统计 Token 和请求数根本不需要网络层做代理拦截；
2. **配置切换靠文件覆写**：
   在 CC Switch 主界面点击提供商卡片，CC Switch 会直接将该卡片保存的 TOML 配置内容写回 `~/.codex/config.toml`；
3. **本地路由（15721）主要针对无法改 API 地址的客户端**：
   Codex 原生支持 `base_url` 直连云端，强行引入 15721 端口会破坏双向 Responses 流式传输并引入本地代理环路。

---

## 3. 标准解决方案：CC Switch 多版本热备切换法 (Best Practice)

为了避免升级后“改错配置引发假死、又无法快速回退”的风险，采用**CC Switch 多版本独立卡片热备策略**：

### 步骤一：在 CC Switch 中新增新版本专用卡片
不修改原有已经验证稳定的 `cpx_1777v2` 配置，而是作为独立副本新增一条 `cpx_22138`：
- **卡片名称**：`cpx_22138`
- **副标题说明**：`Codex Desktop 26.924.22138 适配配置`
- **配置内容**：保持 `base_url = "https://cpx.040926.xyz/v1"` 直连与 `requires_openai_auth = true`，仅将 7 处路径精准对齐为本地最新生成的物理路径：
  ```toml
  notify = ["C:\\Users\\Administrator\\AppData\\Local\\OpenAI\\Codex\\runtimes\\cua_node\\b63ee7ee40c23b77\\bin\\node_modules\\@oai\\sky\\bin\\windows\\codex-computer-use.exe", "turn-ended"]

  [model_providers.custom]
  name = "CPA Direct"
  base_url = "https://cpx.040926.xyz/v1"
  wire_api = "responses"
  requires_openai_auth = true
  supports_websockets = false
  experimental_bearer_token = "sk-cpa-cfa8cfc9c5e3caaa208b999a"

  [mcp_servers.node_repl]
  command = 'C:\Users\Administrator\AppData\Local\OpenAI\Codex\runtimes\cua_node\b63ee7ee40c23b77\bin\node_repl.exe'
  
  [mcp_servers.node_repl.env]
  NODE_REPL_NODE_MODULE_DIRS = 'C:\Users\Administrator\AppData\Local\OpenAI\Codex\runtimes\cua_node\b63ee7ee40c23b77\bin\node_modules'
  NODE_REPL_NODE_PATH = 'C:\Users\Administrator\AppData\Local\OpenAI\Codex\runtimes\cua_node\b63ee7ee40c23b77\bin\node.exe'
  NODE_REPL_TRUSTED_CODE_PATHS = 'C:\Users\Administrator\.codex;C:\Users\Administrator\AppData\Local\OpenAI\Codex\runtimes\cua_node\b63ee7ee40c23b77\bin\node_modules'
  BROWSER_USE_CODEX_APP_VERSION = "26.924.22138"
  NODE_REPL_TRUSTED_SERVICES = '{"browser":"C:/Users/Administrator/.codex/plugins/cache/openai-bundled/browser/26.924.22138/scripts/browser-service.mjs","sky":"@oai/sky/service"}'
  CODEX_CLI_PATH = 'C:\Users\Administrator\AppData\Local\OpenAI\Codex\bin\faa963e871dd422c\codex.exe'
  ```

### 步骤二：开启 CC Switch 登录态保活（防 auth.json 误删）
在 `~/.cc-switch/settings.json` 中确认开启 `"preserveCodexOfficialAuthOnSwitch": true`（详见 Case 007）。这能防止 CC Switch 在卡片切换时将官方登录态物理删除，确保左下角 Team 身份徽标始终在线。

同时，无需特意去手动关闭 CC Switch 的本地路由服务，Codex 直连云端 CPA 与 CC Switch 内部监听完全可以共存，互不干扰。

### 步骤三：毫秒级切换与双向兜底
- 日常运行使用 `cpx_22138`，完美匹配新版本的所有 CUA 与浏览器能力；
- 若遇新版本异常，直接在 CC Switch 界面一键切回 `cpx_1777v2`，即刻回滚。

---

## 4. 验证与实机验收成果 (Verification)

新配置切换就绪后，直接在底层运行 JavaScript 测试 `@oai/sky` 驱动：

```javascript
const { sky } = await import("@oai/sky");
const wins = await sky.list_windows();
console.log("检测到桌面窗口数量:", wins.length);
```

**实测输出结果**：
- 成功发现当前打开的 11 个物理窗口（包含 `CC Switch`、`ChatGPT`、`v2rayN`、`QQ`、`Taskmgr` 等）；
- 成功激活目标窗口并完成硬件级截图与无障碍树提取；
- 证实 Computer Use 核心引擎（Sky）、安全接管遮罩（Computer Use Overlay）及 `escapeToCancel` 机制全部工作正常。

---

## 5. 总结口诀

> **版本升级哈希变，旧版路径成死链。**  
> **开关路由切莫开，直连网关最强悍。**  
> **多建卡片做热备，新旧秒切无风险。**
> **登录保活常驻开，官方凭证不被删。**
