# Case 007: CC Switch 切换第三方供应商导致官方 auth.json 物理删除与登录态丢失深度排查（源码级 preserve_official_auth 机制与短路桥接契约）

- **故障级别**：P1（切换卡片后客户端左下角头像消失、降级为纯 API 模式、CUA 与商业版功能被阉割）
- **涉及组件**：CC Switch (`~/.cc-switch/settings.json`、`cc-switch.db`、`farion1231/cc-switch` 源码)、Codex Desktop (`~/.codex/auth.json`、`config.toml`)、自建 CPA 网关
- **核心定位**：彻底查明 CC Switch 切换第三方卡片时抹杀官方登录态的源码级机理，建立“登录态保活 + 短路桥接契约 + 密钥强对齐”的标准化治理范式
- **实测验收标准**：CC Switch 切换卡片后 `auth.json` 完好存活，Codex Desktop 左下角恢复 Team 登录态与用户头像，CPA 网关 API Key 验证 HTTP 200 通过

---

## 1. 现象与典型踩坑现场 (Symptoms & The Incident)

### (1) 故障现场还原：神秘消失的登录态
在深度整合自建 CPA 网关与 CC Switch 配置切换器的过程中，遇到了一个极其诡异且极具迷惑性的现象：
1. **本地还原看似成功**：在终端通过备份脚本将官方 Team 凭据完整复制到 `C:\Users\Administrator\.codex\auth.json`，通过哈希比对确认完全一致；
2. **只要点 CC Switch 就丢**：然而，只要在 CC Switch 软件主界面点击或激活任何非官方卡片（如 `cpx_22138`），随后重启 Codex Desktop；
3. **界面当场退化**：客户端界面左下角红框处仅剩下“问号（帮助）”和“设置（齿轮）”两个图标，原有的用户头像、邮箱地址以及 Team 订阅徽标荡然无存！
4. **功能遭到严重阉割**：由于退化为纯 API 模式，原本可用的 CUA 电脑操控（`@电脑`）、⚡ Fast 极速速率选择器、远程配对等高级菜单全数隐退。

### (2) 本地备份 22138.txt 的脱节与困惑
此前在排查版本升级时导出的桌面备份 `C:\Users\Administrator\Desktop\22138.txt`，由于当时未探明 CC Switch 底层的登录态保留机制，其中第 39 行标记为 `requires_openai_auth = true`，但在未开启登录态保留的情况下，每次被 CC Switch 同步写入本地时都会引发冲突或被强行覆盖，导致本地备份与实际生效配置产生割裂。

---

## 2. 根因深度剖析：CC Switch 源码级真相 (Root Cause Analysis)

通过直接检索并审查 `farion1231/cc-switch` 官方仓库核心源码（`src-tauri/src/codex_config.rs` 与 `src-tauri/src/settings.rs`），彻底揭开了这一“幽灵失踪案”的技术真相：

### (1) 核心源码证据 1：切换第三方卡片默认物理删除 `auth.json`
在 `codex_config.rs` 的 `plan_codex_live_write` 与 `write_codex_live_for_provider` 函数中：

```rust
// Third-party switches are config-only...
// The preservation setting decides whether the official login in
// auth.json survives a third-party switch. Off means the file is
// deleted — a lingering login next to a third-party route is the leak
// shape the gates exist to prevent...
let remove_auth_file = !preserve_official_login;

...

if plan.remove_auth_file {
    remove_codex_live_auth_after_third_party_switch();
}

fn remove_codex_live_auth_after_third_party_switch() {
    let auth_path = get_codex_auth_path();
    if !auth_path.exists() {
        return;
    }
    if let Err(e) = delete_file(&auth_path) {
        log::warn!("Failed to remove auth.json after a third-party Codex switch: {e}");
    }
}
```

- **真相大白**：CC Switch 设计团队出于“防止向第三方网关意外泄露官方 OAuth 凭证”的考量，设定了**只要切换到非官方卡片，就必须物理删除 `~/.codex/auth.json`** 的硬逻辑！
- 这就是为什么无论你在本地手动执行多少次 `Copy-Item auth.json`，只要你在 CC Switch 界面上点击了该卡片，CC Switch 的 Rust 后台就会以毫秒级速度立即把 `auth.json` 文件物理删除！

### (2) 核心源码证据 2：设备级配置默认处于关闭状态
在 `settings.rs` 中：

```rust
pub preserve_codex_official_auth_on_switch: bool,

// 默认值初始化:
preserve_codex_official_auth_on_switch: false,
```

在设备级配置文件 `~/.cc-switch/settings.json` 中：
```json
"preserveCodexOfficialAuthOnSwitch": false
```
该字段默认即为 `false`！这意味着任何未经额外深度定制的 CC Switch 客户端，只要点击非官方卡片，就会无条件触发物理删除逻辑。

### (3) 连锁反应：纯 API Key 模式导致前端界面被降级
当 `auth.json` 被物理删除后：
1. Codex Desktop 启动时读取不到合法的 JWT Claims（找不到 `chatgpt_plan_type: "team"` 与 `account_id`）；
2. 前端策略引擎直接判定当前运行在匿名/纯 API Key 模式下；
3. 左下角移除所有账号信息展示，界面高级特性菜单全部置灰或移除（详见 [Case 003](003-codex-hybrid-auth-cpa-architecture.md)）。

---

## 3. 核心机制：短路桥接契约 (Preservation-Mode Bridge Contract)

CC Switch 源码实际上提供了一套非常精妙的解决方案——**保留模式短路桥接契约（Preservation-Mode Bridge Contract）**。

### (1) 开启 `preserveCodexOfficialAuthOnSwitch = true` 后的工作流
当在设置中将该选项置为 `true` 时：
1. **文件保活**：`remove_auth_file = false`，切换卡片时绝对不碰 `auth.json`，官方凭据永久常驻本地；
2. **配置自动对齐**：函数 `align_codex_requires_openai_auth_with_login_preservation` 会自动将 TOML 配置中的 `requires_openai_auth` 对齐修改为 `true`；
3. **短路鉴权生效（Short-Circuiting Request Auth）**：
   在 `codex_config.rs` 中明确实现：
   ```rust
   // With a token present the injected bearer short-circuits the fallback instead (bridge contract)
   let short_circuits_request_auth = provider_table.get("experimental_bearer_token").is_some()
       || provider_table.get("env_key").is_some();
   ```

### (2) 双轨架构完美闭环
通过该契约，实现了鱼与熊掌兼得的完美状态：
- **控制平面（Control Plane）**：Codex 前端读取常驻的 `auth.json`，验证通过 Team 身份断言，在界面左下角完美显示用户头像与登录名，解锁 CUA 等全量商业版特性；
- **数据平面（Data Plane）**：由于 TOML 中显式配置了 `experimental_bearer_token = "sk-cpa-cfa8cfc9c5e3caaa208b999a"`，Codex 底层在向 `base_url`（自建 CPA）发送请求时，会自动短路掉官方鉴权，**100% 携带指定的 CPA API Key 进行通信，绝不会将官方凭证误传给自建端点**！

---

## 4. 标准实战治理四步法 (Step-by-Step Remediation)

### 步骤一：开启 CC Switch 登录态保活并重启进程
编辑 `C:\Users\Administrator\.cc-switch\settings.json`，将保活开关打开：

```json
{
  ...
  "preserveCodexOfficialAuthOnSwitch": true,
  ...
}
```

保存后，重启 `cc-switch.exe` 进程，确保内存储存的全局设置完成重载。

### 步骤二：在 CC Switch 中重建/更新规范卡片
在 CC Switch 数据库 `~/.cc-switch/cc-switch.db` 中，确保卡片包含以下完整要素：
- **供应商名称**：`cpx_22138`
- **副标题说明**：`Codex Desktop 26.924.22138 适配配置`
- **API 密钥**：严格核实为 `sk-cpa-cfa8cfc9c5e3caaa208b999a`（绝不能填错或遗漏）
- **接口地址**：`https://cpx.040926.xyz/v1`
- **内部 TOML 模板**：
  ```toml
  # 唯一模型提供方：CPA 云端直连
  [model_providers.custom]
  name = "CPA Direct"
  base_url = "https://cpx.040926.xyz/v1"
  wire_api = "responses"
  requires_openai_auth = true
  supports_websockets = false
  experimental_bearer_token = "sk-cpa-cfa8cfc9c5e3caaa208b999a"
  ```

### 步骤三：从黄金备份还原官方 `auth.json`
确保官方凭证就位：
```powershell
Copy-Item -LiteralPath "D:\codex-auth-backup\auth.json" -Destination "C:\Users\Administrator\.codex\auth.json" -Force
```

### 步骤四：重新校准并导出桌面备份 `22138.txt`
重新生成干净无 BOM 的 `C:\Users\Administrator\Desktop\22138.txt`，使本地查阅备份与当前实机 `config.toml` 以及 CC Switch 数据库中的内容 100% 逐行对齐。

---

## 5. 验证与实机验收成果 (Verification)

1. **设置持久化检验**：核验 `~/.cc-switch/settings.json`，`preserveCodexOfficialAuthOnSwitch` 稳定为 `true`；
2. **CPA 连通性与密钥验证**：
   使用 Node 原生 HTTP 携带 `sk-cpa-cfa8cfc9c5e3caaa208b999a` 向 `https://cpx.040926.xyz/v1/models` 发送请求，返回 **HTTP 200 OK**，成功解析 43 个模型池；
3. **实机界面验收**：
   在 CC Switch 激活 `cpx_22138` 的前提下，重启 Codex Desktop，**左下角清晰展示用户头像与 Team 登录标识，登录态完全回归**！

---

## 6. 避坑口诀与常驻红线

> **切莫盲猜登录丢，源码审查解烦忧。**  
> **保活开关必须开，凭据常驻免遭害。**  
> **密钥对准短路桥，控制数据两相宜。**
