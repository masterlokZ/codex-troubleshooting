# Case 003: Codex 混合登录态（官方 auth.json + 自建 CPA 网关）实现全功能原生体验与流量自主可控

- **案例编号**：Case 003
- **级别**：架构深度解析与实战最佳实践
- **核心架构模式**：控制面（Control Plane）与数据面（Data Plane）双轨解耦
- **涉及组件**：Codex Desktop 前端 (UI / Electron)、`app-server` (Rust/Node 底层服务)、`auth.json` (OAuth 凭据)、`config.toml` (核心路由配置)、`model-catalog.json` (模型能力目录)、CLIProxyAPI (CPA 网关)
- **交付目标**：零侵入反编译、免改 ASAR、解锁全量原生高级功能菜单（CUA 电脑操控、远程连接、应用快照、Worktrees、用量查询等）、点亮“闪电/Fast”速率选择器，同时实现推理流量 100% 私有网关接管与自主可控。

---

## 1. 背景与核心痛点 (Background & Pain Points)

在深度定制与使用 OpenAI Codex Desktop 客户端的过程中，许多开发者与企业工程团队希望将模型推理流量接入内网自建的统一网关（如 CLIProxyAPI / CPA、中转聚合或企业内网私有代理），以获得多上游负载均衡、高并发削峰、配额熔断降级等企业级治理能力。但在实操中，传统方案往往面临以下三大核心痛点：

### (1) 纯 API 模式导致前端被严重“阉割”
当客户端仅配置 `OPENAI_API_KEY` 或将认证模式声明为纯 API Key 模式（`auth_mode = "api_key"`）时，Codex Desktop 前端会判定当前运行在极简开发者/纯代码模式下，从而在 UI 上强制裁剪并隐藏大量原生核心高级能力：
- **丢失远程连接** (Remote Connections & Host Pairing)：无法与局域网或云端其他 Codex 主机建立主从配对与任务桥接。
- **丢失电脑操控 CUA** (Computer Use Agent / Sky 运行时)：CUA 权限门禁直接锁定，无法唤醒本地浏览器操控与桌面原生自动化代理。
- **丢失应用快照与环境隔离** (App Snapshots & Environments)：无法管理运行时依赖包快照与本地工作区沙盒。
- **丢失 Worktrees 树状隔离** (Git Worktrees Lifecycle)：侧边栏多分支并行工作树管理入口被彻底移除。
- **丢失使用量与额度查询** (Usage Limits Query)：无法获取账户层级的实时额度窗口与重置时间看板。
- **设置菜单重度缩水**：多智能体协作（Multi-Agent）、实验性功能开关等入口全数置灰或隐藏。

### (2) 界面无法调出“闪电/Fast”速率选择器图标
在官方高阶套餐（如 Team / Pro / Enterprise）中，Codex 界面提供“闪电”（⚡ Fast / Priority Tier）切换功能，支持 2x 加速与优先级通道。但在接入自定义网关或自定义模型目录后，界面的 Fast 图标通常神秘消失，或者点击毫无反应，思考档位（Reasoning Effort）与高阶模型参数也无法完整呈现。

### (3) 反编译破解客户端极其脆弱，升级即失效
部分团队为了绕过上述限制，尝试解包 `app.asar` 反编译前端 JavaScript 代码，强行修改 React 组件内的条件渲染逻辑（如硬编码绕过 `isChatGPTAccount` 检查）。这种逆向方案存在致命缺陷：
- **升级即覆灭**：Codex 拥有静默热更新机制，任何小版本迭代都会整体覆盖 `app.asar`，导致补丁立刻失效。
- **代码指纹与完整性校验风险**：Electron 新版本强化了运行时 ASAR 完整性哈希校验，篡改安装包容易导致启动闪退、白屏或被风控阻断。
- **难以工程化标准化**：团队中每台开发机都需要重新反编译、重新打补丁，维护成本极高。

---

## 2. 架构深度剖析：控制面与数据面双轨分离模型 (Architecture Deep-Dive)

要彻底、优雅、原生且免入侵地解决上述问题，最佳架构范式是**控制平面（Control Plane）与数据平面（Data Plane）双轨解耦模型**。

### 架构全景拓扑图

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        Codex Desktop (UI Layer)                        │
│                                                                        │
│   [全量高级设置]   [电脑操控 CUA]   [远程主机配对]   [⚡ Fast 速率图标]      │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
       ┌────────────────────────────┴───────────────────────────┐
       │                                                        │
       ▼ (本地只读读取)                                          ▼ (JSON 规格解析)
┌──────────────┐                                       ┌──────────────────┐
│  auth.json   │ ◄─── 【控制平面 Control Plane】        │model-catalog.json│
│ (官方登录凭证) │      - 身份断言: chatgpt_plan_type     │  (模型能力声明)  │
└──────────────┘      - 组织断言: account_id / org_id   └────────┬─────────┘
                      - 激活全量商业版前端功能                  │
                                                                │ 共同驱动
                                                                ▼
                                                       ┌──────────────────┐
                                                       │ 双重状态机判定:  │
                                                       │ ⚡ Fast 图标点亮 │
                                                       └──────────────────┘
                                    │
                                    ▼ (模型调用分发)
┌────────────────────────────────────────────────────────────────────────┐
│                        app-server (Runtime Core)                       │
│                                                                        │
│  读取 config.toml:                                                      │
│    model_provider = "custom"                                           │
│    base_url = "https://cpx.040926.xyz/v1"                              │
│    requires_openai_auth = true                                         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼ 【数据平面 Data Plane】(100% 流量接管)
┌────────────────────────────────────────────────────────────────────────┐
│                      自建私有 CPA 网关 (CLIProxyAPI)                     │
│                                                                        │
│  - 请求头透传与清洗 (Header Sanitization & Mapping)                     │
│  - 动态模型映射与调度 (gpt-6-astra -> 多上游模型池)                     │
│  - 配额熔断与无感故障转移 (Failover & Circuit Breaking)                 │
│  - 响应流定制与上下文补丁 (Response Stream Patching)                   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. 核心机制 1：控制平面身份断言与高级功能解锁

Codex Desktop 的前端界面在初始化与渲染时，采用的是**本地离线身份断言（Local Identity Assertion）**机制，而非每次渲染都与远程服务器进行强一致的鉴权握手：

1. **凭证加载与 JWT 解析**：
   客户端启动时，`app-server` 会读取本地 `C:\Users\<User>\.codex\auth.json`。该文件中包含经过官方 OAuth 认证后的 `tokens`（`access_token` 与 `id_token`）。
2. **Claims 提取与功能树唤醒**：
   前端解码 `id_token` 或 `access_token` 中的 JWT Claims：
   ```json
   {
     "https://api.openai.com/auth": {
       "chatgpt_plan_type": "team",
       "chatgpt_account_id": "c3044ded-...",
       "chatgpt_user_id": "user-..."
     }
   }
   ```
3. **功能门禁放行**：
   只要 `chatgpt_plan_type` 命中 `team`、`pro`、`business`、`enterprise` 等付费计划，前端的策略引擎就会无条件全量唤醒：
   - 激活侧边栏与设置页面的“远程连接”（Remote Connections）管理模块；
   - 激活 Computer Use Agent（CUA）的原生运行时连接管道；
   - 激活工作树管理（Worktrees）、沙盒配置与配额监控面板。

**结论**：保持本地存在一个合法有效的官方 `auth.json`（即便该账号的基础配额已经用完，或者无需走该账号计费），即可永久稳定地作为**控制平面身份钥匙**，100% 原生唤醒所有客户端高级特性。

---

## 4. 核心机制 2：数据平面 100% 流量接管与 CPA 调度

解锁了全量 UI 后，如何确保实际的模型推理、代码生成、Tool Call 流量**不走**官方默认链路，而是**100% 受控地流向私有 CPA 网关**？

这通过 `C:\Users\<User>\.codex\config.toml` 的路由机制完成：

```toml
model_provider = "custom"
model = "gpt-6-astra"

[model_providers.custom]
name = "CPA Direct"
base_url = "https://cpx.040926.xyz/v1"
wire_api = "responses"
requires_openai_auth = true
supports_websockets = false
experimental_bearer_token = "sk-cpa-xxxxxxxxxxxxxxxxxxxxxxxx"
```

### 运行时接管过程
1. **全局 Provider 劫持**：将 `model_provider` 设为 `"custom"`，通知 `app-server` 绕过官方默认的端点。
2. **协议对齐（`wire_api = "responses"`）**：Codex Desktop 深度依赖 OpenAI 最新的双向流式 `responses` 协议。自建 CPA 网关实现对 `responses` 协议的完全兼容与响应流代理。
3. **网关层自主可控**：所有的提示词、补全请求、上下文窗口以及工具调用输出，全部经过 `https://cpx.040926.xyz/v1` 传输。自建 CPA 网关可在内网层面实现：
   - 多 Key 轮询与智能负载均衡；
   - 单账号 429 速率限制检测与毫秒级故障转移；
   - 超长上下文自动截断或自定义压缩适配；
   - 私有审计与日志分析。

---

## 5. 核心机制 3：闪电极速按钮 (⚡ Fast) 的双重触发状态机

许多工程师在定制模型目录时，发现界面上的“⚡ Fast”速率选择器图标死活出不来。经过底层逻辑逆向与代码溯源，前端点亮 Fast 切换按钮依赖一个严格的**双重触发状态机（Dual-Trigger State Machine）**：

```text
Fast 按钮点亮 <=> 控制面身份断言成功 AND 模型目录能力显式声明
```

### 条件 1：控制面身份断言 (Identity Assertion)
`auth.json` 中的当前登录态必须拥有 Priority Tier 权限（即 `chatgpt_plan_type` 必须为 `team`、`pro`、`business`、`enterprise` 或支持 fast 的订阅类型）。如果是普通免费版账号（`free`），前端直接隐藏该图标。

### 条件 2：模型目录能力显式声明 (Capability Declaration)
在本地引用的 `model-catalog.json` 中，目标模型的配置对象必须显式包含两个核心字段：

1. **`service_tiers` 数组**：必须明确声明 `priority` 档位对象：
   ```json
   "service_tiers": [
     {
       "id": "priority",
       "name": "Fast",
       "description": "2x speed, increased usage"
     }
   ]
   ```
2. **`additional_speed_tiers` 数组**：必须包含 `"fast"`：
   ```json
   "additional_speed_tiers": [
     "fast"
   ]
   ```

### 常见失效排查矩阵

| `auth.json` 身份 | `model-catalog.json` 声明 | 界面表现 | 根因剖析 |
| :--- | :--- | :--- | :--- |
| Free 账号 | 含 `priority` service tier | ❌ 隐藏 | 身份无权享受 Fast 通道，前端拒绝显示 |
| Team / Pro 账号 | `service_tiers: []`（空数组） | ❌ 隐藏 | 虽有身份，但该模型未声明支持极速档位 |
| Team / Pro 账号 | 缺少 `additional_speed_tiers` | ⚠️ 异常或置灰 | 速度档位状态机未完全激活 |
| **Team / Pro 账号** | **完整包含 `service_tiers` 与 `additional_speed_tiers`** | **✅ 完美点亮 ⚡ Fast 图标** | **两项充要条件同时满足，状态机闭环** |

---

## 6. 核心机制 4：`requires_openai_auth = true` 机制与 Token 安全边界

在 `[model_providers.custom]` 中，`requires_openai_auth = true` 是一个非常关键的配置项。

### (1) 机制原理
当配置为 `true` 时，`app-server` 在向 `base_url` 发送模型请求时，会从本地 `auth.json` 中提取最新的 OAuth Bearer Token（或由客户端刷新的临时 session token），并注入到 HTTP 请求的 `Authorization: Bearer <token>` 请求头中。

### (2) 为什么自建 CPA 需要它？
- **握手协议完整性**：Codex 前端与 `app-server` 的通信协议假定当前运行在全功能 ChatGPT 交互链路中，开启此选项能保证所有上下游请求头格式与官方协议 100% 镜像一致。
- **网关鉴权与租户隔离**：自建 CPA 可以在网关入口处解析该 Token，读取用户身份以完成内部团队计费、权限路由，或验证客户端合法性。

### (3) 核心安全铁律与边界警示

> **高危安全红线**：
>
> 1. **仅限指向自建私有或可信 CPA**：由于 `requires_openai_auth = true` 会将你真实的官方 OAuth Access Token 随请求发送，**绝对严禁**将 `base_url` 配置为未经代码审计的公网第三方反代、公共中转站或不可信的个人代理！
> 2. **Token 泄露危害**：如果将附带官方 Token 的请求发送给恶意或不受控的第三方节点，对方将直接获得你官方账号的完整 API 与会话操作权限，导致账号被盗用或封禁。
> 3. **私网隔离最佳实践**：自建 CPA 必须部署在受控内网、本地 Docker 或具备严格 HTTPS + IP 访问控制的私有 VPS 上，确保数据面链路绝对安全。

---

## 7. 配置文件标准化范式 (Configuration Blueprints)

### (1) 核心路由配置：`config.toml`（脱敏生产范式）

文件路径：`C:\Users\<User>\.codex\config.toml`

```toml
# ==============================================================================
# Codex Desktop 混合架构生产配置
# 控制面：auth.json 官方 Team/Pro 身份保活
# 数据面：custom provider 直连自建 CPA 网关 (100% 流量自主可控)
# ==============================================================================

model_provider = "custom"
model = "gpt-6-astra"

# 上下文与压缩阈值调优 (适配自建长文本)
model_context_window = 1000000
model_auto_compact_token_limit = 900000
model_auto_compact_token_limit_scope = "total"
model_post_turn_compact_threshold_percent = 90
tool_output_token_limit = 1000000
disable_response_storage = true
service_tier = "default"

# 权限与沙盒模式
approval_policy = "never"
default_permissions = ":danger-full-access"
sandbox_mode = "danger-full-access"
web_search = "live"

# 自定义模型目录 (必须确保为 UTF-8 无 BOM 格式)
model_catalog_json = 'C:\Users\Administrator\Desktop\1444-model-catalog.json'

# 核心数据平面：自建私有 CPA 网关
[model_providers.custom]
name = "CPA Direct"
base_url = "https://cpx.040926.xyz/v1"
wire_api = "responses"
requires_openai_auth = true
supports_websockets = false
experimental_bearer_token = "sk-cpa-production-token-example"

# 全功能特性开关 (解锁 Multi-Agent 与 Goals)
[features]
goals = true
multi_agent = true

[features.multi_agent_v2]
enabled = true
max_concurrent_threads_per_session = 20
wait_agent_enabled = true
expose_spawn_agent_model_overrides = true

# 前端桌面显示微调
[desktop]
conversationDetailMode = "STEPS_COMMANDS"
sansFontSize = 14
codeFontSize = 13
default-service-tier = "default"
enabled-reasoning-efforts = ["low", "medium", "high", "xhigh", "ultra", "persistent", "max"]
```

### (2) 模型能力目录：`model-catalog.json` 核心片段

在自定义模型目录中，配置支持 Fast 速率选择器与思考档位调节的标准 JSON 条目：

```json
{
  "models": [
    {
      "slug": "gpt-6-astra",
      "display_name": "GPT-6-Astra",
      "description": "Enterprise-grade high-throughput reasoning model.",
      "comp_hash": "3000",
      "context_window": 1000000,
      "auto_compact_token_limit": 900000,
      "apply_patch_tool_type": "freeform",
      "shell_type": "shell_command",
      "supported_in_api": true,
      "available_in_plans": [
        "business",
        "enterprise",
        "pro",
        "team"
      ],
      "additional_speed_tiers": [
        "fast"
      ],
      "service_tiers": [
        {
          "id": "priority",
          "name": "Fast",
          "description": "2x speed, prioritized throughput"
        }
      ],
      "default_reasoning_level": "xhigh",
      "supported_reasoning_levels": [
        { "effort": "low", "description": "低" },
        { "effort": "medium", "description": "中" },
        { "effort": "high", "description": "高" },
        { "effort": "xhigh", "description": "超高" }
      ]
    }
  ]
}
```

---

## 8. 避坑指南与排障速查 (Troubleshooting & Pitfalls)

### 坑点 1：`model-catalog.json` 编码包含 UTF-8 BOM 导致假死报错
- **现象**：修改完模型目录后，启动提示 `Unable to load sign-in requirements`。
- **根因**：Windows 工具（如 PowerShell 默认重定向）写入了 `0xEF 0xBB 0xBF` 前导字节，导致 JSON 解析器崩溃（详见 [Case 001](001-model-catalog-utf8-bom-crash.md)）。
- **铁律**：所有 JSON 配置文件必须严格保存为 **UTF-8 无 BOM**（UTF-8 without BOM）格式。可用以下脚本快速校验：
  ```powershell
  pwsh -File D:\codex-troubleshooting\scripts\check-and-strip-bom.ps1 -Path C:\Users\Administrator\Desktop\1444-model-catalog.json
  ```

### 坑点 2：官方 `auth.json` 长期离线导致 Session 失效
- **现象**：数周后客户端偶尔弹出重新登录提示，控制面部分功能暂时隐退。
- **应对措施**：
  1. 通过官方客户端重新完成一次标准网页 OAuth 登录，生成最新有效的 `auth.json`；
  2. 备份该文件中的有效 JWT Tokens（通常有效期较长）；
  3. 自建 CPA 并不消耗该官方账号的用量余额，仅需借用其身份凭据维持客户端前端的特性激活。

### 坑点 3：CPA 网关反向代理超时导致大推理模型截断
- **现象**：在超长思考档位（如 `ultra` / `max`）或大项目审查下，生成到一半界面报错网络超时或断流。
- **排查要点**：
  - CPA 前置的反向代理（如 Nginx、Caddy 或 Cloudflare）必须开启 SSE 长连接配置：
    - `proxy_buffering off;`
    - `proxy_read_timeout 86400s;`
    - `proxy_send_timeout 86400s;`
  - 确保心跳保活帧（Ping / Comment Frame）正常透传，避免被上游网关因空闲连接而掐断。

### 坑点 4：CC Switch 切换第三方卡片默认物理删除 `auth.json`
- **现象**：本地明明备份还原了官方 `auth.json`，但只要在 CC Switch 界面上点击或激活任何非官方卡片，重启 Codex Desktop 后左下角头像瞬间消失，界面再次退化为纯 API 模式。
- **根因**：CC Switch 内部代码设定 `remove_auth_file = !preserve_official_login`，且设备级配置 `~/.cc-switch/settings.json` 中 `"preserveCodexOfficialAuthOnSwitch"` 默认处于 `false` 状态，每次切换卡片都会无情删除 `auth.json`！
- **治理铁律**：必须在 `~/.cc-switch/settings.json` 中将 `"preserveCodexOfficialAuthOnSwitch"` 设置为 `true`，触发官方短路桥接契约（详见 [Case 007](007-cc-switch-official-auth-preservation-and-bridge-contract.md)）。

---

## 9. 架构演进与最佳实践总结 (Golden Rules)

1. **控制面归官方，数据面归私有**：利用官方 `auth.json` 本地断言完美激活原生 UI（CUA、远程配对、高级管理），利用 `config.toml` 的 custom provider 将推理流量 100% 路由至私有 CPA。
2. **零改动 ASAR，全功能纯配**：彻底摒弃反编译修改客户端代码的脆弱反模式，所有高级特性与行为全部通过合规配置文件驱动，实现版本平滑静默升级。
3. **双重状态机点亮 Fast 图标**：掌握 `auth.json` 付费计划断言与 `model-catalog.json` 中 `service_tiers` + `additional_speed_tiers` 的协同关系，按需解锁极速速率选择器。
4. **筑牢私网防线，绝不裸奔 Token**：启用 `requires_openai_auth = true` 时，端点必须严格限定在私有受信 CPA 网关内部，绝不向不可信的第三方代理泄露官方身份凭证。
