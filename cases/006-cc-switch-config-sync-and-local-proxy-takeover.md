# Case 006: CC Switch 双重工作模式（配置同步器 vs 15721 本地路由接管）深度解耦与防死循环避坑指南

- **故障级别**：P1（自环死循环转发引发熔断器打满、HTTP 502 连环雪崩；CC Switch 架构认知偏差）
- **涉及组件**：CC Switch（Desktop GUI / Axum 本地代理）、Codex Desktop（`~/.codex/config.toml`）、自建 CPA 网关（`https://cpx.040926.xyz/v1`）
- **核心定位**：彻底解耦 CC Switch 的“配置同步器（Switcher）”与“本地路由代理（Proxy Service）”双重机制，消除手动硬编码 `127.0.0.1:15721` 引发的自环雪崩
- **实测验收标准**：明确卡片配置与本地配置的真实边界，直连模式零代理开销稳定运行，路由模式全自动透明接管

---

## 1. 故障现象与典型事故现场 (Symptoms & The Incident)

### (1) 事故现场还原：29 秒爆发 8000+ 次内部死循环
在排查 CC Switch 连通性时，曾尝试将 Codex 配置或者 CC Switch 供应商配置修改为本地代理端点 `http://127.0.0.1:15721/v1`，随后整个 API 调用直接报废：
- 客户端立即报出请求失败；
- 翻查 `~/.cc-switch/logs/` 历史日志，发现瞬间爆发大量如下报错：
  ```text
  请求目标: http://127.0.0.1:15721/v1/responses
  熔断器触发: 连续失败 4 次 -> Open
  cause: 上游 HTTP 502: CC Switch local proxy failed...
  cause: 转发失败: 上游连接失败
  ```
- **客观统计**：在短短 29 秒内，本地代理自身向自身发起了超过 **8000 次** 递归嵌套调用，打爆 Axum 监听队列与熔断器（CircuitBreaker），引发级联 HTTP 502 报错。

### (2) 用户交互层面的认知冲突
- 用户发现：“我在 CC Switch 里的那个配置一改，它就会立刻同步覆盖修改本地的 `config.toml`！”
- “既然 CC Switch 会把卡片内容直接写进 `config.toml`，那官方文档里写的 `base_url = "http://127.0.0.1:15721/v1"` 到底应该填在什么地方？为什么一填就挂？”

---

## 2. 根因深度剖析 (Root Cause Analysis)

通过并发审查 CC Switch 官方源码（`farion1231/cc-switch` 的 Axum 转发引擎）、数据库架构（`cc-switch.db`）与实机进程状态，确认 CC Switch 具有两套完全不同层级的运行逻辑：

### (1) 核心身份：CC Switch 首先是一个“配置同步器（Switcher）”
- **同步逻辑**：用户在 CC Switch 界面中新建或编辑卡片（如 `cpx_22138`），并在列表中点击“启用”按钮时，CC Switch 的本质动作是**文件覆写**——它直接将该卡片保存的完整 TOML 文本，原封不动地同步写入 `~/.codex/config.toml`。
- **致死自环诱因**：若用户或脚本误将卡片中的 `base_url` 手动填写成了 `http://127.0.0.1:15721/v1`：
  1. 点击“启用”后，`config.toml` 里的 `base_url` 被写入为 15721；
  2. Codex 客户端发起请求，打到本地 15721 端口；
  3. 监听 15721 的 CC Switch 读取当前激活卡片的配置获取上游端点，赫然发现上游也是 15721；
  4. CC Switch 将请求再次打给 15721，引发自身循环调用自身（Self-Forwarding Infinite Loop），瞬间触发熔断雪崩。

### (2) 高阶扩展：官方文档中的 `127.0.0.1:15721` 是“软件后台动态接管”
- 官方文档中提及的 `15721` 端口，属于 CC Switch 内置的高级特性——**本地路由服务（Local Proxy Service）**。
- **其真实定位与适用场景**：
  - 用于多模型故障转移（Failover）；
  - 用于协议转译（将第三方不支持 Responses 协议的 Chat Completions 或 Anthropic Messages 接口实时转为 Responses 流）；
  - 敏感 Key 占位隔离（用 `PROXY_MANAGED` 隐藏真实凭证）。
- **运作机制**：
  - 该模式**完全不需要用户在任何卡片或输入框中手动填写 15721**；
  - 只要卡片内保持填写远端真实地址（如 CPX），当用户在 CC Switch 设置中开启“本地路由”并勾选“Codex 接管”时，**CC Switch 软件会自动在内存中启动监听，并在后台临时、自动地把 `config.toml` 改写为 15721**；
  - 当用户关闭接管开关时，软件会自动把 `config.toml` 还原为卡片里的真实云端地址。

---

## 3. 双模式架构对比与正向工程范式 (Best Practice)

明确区分两种使用形态，按需选用：

| 维度 | 模式一：直连切换模式（默认 & 推荐） | 模式二：本地路由代理模式（高级转译） |
| :--- | :--- | :--- |
| **运作机制** | CC Switch 纯做配置文件覆写器 | CC Switch 作为透明中间人反向代理 |
| **卡片 Base URL** | **必须填真实云端地址** (`https://cpx.040926.xyz/v1`) | **必须填真实云端地址** (`https://cpx.040926.xyz/v1`) |
| **Codex config.toml** | `base_url = "https://cpx.040926.xyz/v1"` (直连 CPA) | `base_url = "http://127.0.0.1:15721/v1"` (程序自动覆写) |
| **15721 端口** | 关闭（物理未监听，零系统资源消耗） | 开启（Axum 监听 `127.0.0.1:15721`） |
| **数据流向** | Codex 客户端 -> 直连 CPA -> 大模型 | Codex -> CC Switch (15721) -> CPA -> 大模型 |
| **操作要领** | 卡片填好后，直接点击启用即可 | 卡片填好后，打开 CC Switch 路由接管开关 |

### 正向配置规范片段

#### (1) CC Switch 供应商卡片（唯一真理源）
无论使用何种模式，**在 CC Switch 内部填写的卡片永远只能写真实云端端点**：
```toml
model_provider = "custom"

[model_providers.custom]
base_url = "https://cpx.040926.xyz/v1"
wire_api = "responses"
requires_openai_auth = true
```

#### (2) Codex 客户端配置 (`~/.codex/config.toml`)
- **直连模式下**：由 CC Switch 启用卡片后直接生成，内容与卡片完全一致（直连 `https://cpx.040926.xyz/v1`）；
- **路由接管模式下**：卡片不变，在 CC Switch 开启接管开关后由程序自动改写为 `http://127.0.0.1:15721/v1`，无需人工干预。

---

## 4. 避坑铁律与排错矩阵 (Do's and Don'ts)

1. **严禁在 CC Switch 卡片内硬编码 15721**：
   卡片是 CC Switch 向外发起请求的上游源头。卡片填 15721 = CC Switch 把请求发给自己 = 瞬间死循环。
2. **直连模式是第一优先级**：
   自建 CPA 本身已原生支持完整的 Responses 协议、双向流式与速率控制。直接走直连模式没有中间转发开销，稳定性最高。
3. **遭遇 HTTP 502 / 熔断器开启时的极速排错**：
   若出现 502，优先检查 `~/.cc-switch/cc-switch.db` 中 `providers` 表当前激活记录的 `settings_config`，确认其 `base_url` 是否被污染为 15721。若是，立即物理修正为 `https://cpx.040926.xyz/v1`。
