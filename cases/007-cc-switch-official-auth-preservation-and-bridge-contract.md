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

## 4. 登录态极速恢复全流程操作指南 (Disaster Recovery Runbook)

当遭遇登录态丢失（左下角仅剩问号和齿轮图标、无用户头像与 Team 标识）时，按以下闭环步骤极速恢复：

### 步骤一：一键自愈与自动化健康体检（首选标准操作）
知识库已将经过生产级验证的一键恢复脚本收录至 [scripts/restore-and-verify-auth.ps1](../scripts/restore-and-verify-auth.ps1)。该脚本会自动完成“定位备份 -> 物理复制 -> SHA256 校验 -> JWT 身份解码 -> CC Switch 保活状态检测与自动修复”五位一体全自动流水线：

```powershell
pwsh -File D:\codex-troubleshooting\scripts\restore-and-verify-auth.ps1
```

**预期成功输出示例**：
```text
=== Codex 官方登录态极速恢复与健康体检工具 ===
[定位备份] 选用黄金凭据来源: D:\codex-auth-backup\auth.json
[凭据还原] 已成功将 auth.json 写入: C:\Users\Administrator\.codex\auth.json
[哈希校验] SHA256 完全对齐: 6186A6BF2FB75C784A8C042D8461273158BD330582EBB7ECD817318EDE2BB21A
[身份断言] 账号邮箱: zjh852485809@gmail.com | 订阅类型: team
[防删免疫] CC Switch preserveCodexOfficialAuthOnSwitch = true (常驻免疫开启)
=== 恢复完成！请重启 Codex Desktop 客户端即可看到左下角头像与登录态完全回归 ===
```

### 步骤二：纯手动命令行极速恢复（备用降级方案）
若在极简环境或脚本不可用时，可直接在 PowerShell 7 中单行完成凭据还原与哈希对齐：

```powershell
# 1. 物理还原凭证
Copy-Item -LiteralPath "D:\codex-auth-backup\auth.json" -Destination "C:\Users\Administrator\.codex\auth.json" -Force

# 2. 核验哈希对齐
(Get-FileHash "C:\Users\Administrator\.codex\auth.json").Hash
```

### 步骤三：客户端进程重启与内存重载
Codex Desktop 的前端 Electron 与底层 `app-server` 核心服务在启动时一次性加载凭据并驻留内存。凭证还原落盘后，**必须重启一次客户端主程序**：
1. 退出当前的 Codex Desktop 客户端窗口；
2. 重新启动客户端，观察界面左下角红框区域：用户专属头像、邮箱与 Team 订阅标识即刻完整回归。

---

## 5. 登录态防丢失长效预防与深度防御体系 (Prevention & Defense-in-Depth)

为杜绝“修复一次好一阵，稍不留神又被删”的循环返工，建立以下五层长效深度防御体系：

### 第一道防线：CC Switch 保活开关永久固化（源头阻断误删）
- **核心机制**：在设备级配置文件 `C:\Users\Administrator\.cc-switch\settings.json` 中，必须永久固化：
  ```json
  {
    "preserveCodexOfficialAuthOnSwitch": true
  }
  ```
- **自检与重载**：若手工编辑了 `settings.json`，必须重启 `cc-switch.exe` 进程以重载内存中的全局设置；
- **防版本更新重置**：每次 CC Switch 软件版本升级或重新配置后，将该配置项纳入首要检查清单。

### 第二道防线：多介质冷热双备份策略（防止单点故障）
官方 Team 登录凭据（`auth.json`）属于高价值控制面钥匙，严禁仅在 C 盘（系统盘）单点保存：
1. **D 盘常驻热备份**：保存在 `D:\codex-auth-backup\auth.json`，作为本地日常一键自愈的首选源；
2. **U 盘/移动介质离线冷备份**：保存在 `U:\codex-auth-backup\auth.json`，作为系统崩溃、重装系统或磁盘损坏时的终极保命副本；
3. **备份文件防污染**：严禁直接在备份目录中用文本编辑器编辑 `auth.json`，严禁引入 UTF-8 BOM 头。

### 第三道防线：三位一体配置强对齐规范（彻底消灭配置错位）
必须确保以下三处配置关于认证与路由的参数 100% 逐行完全对齐：
1. **CC Switch 数据库卡片**（`cc-switch.db` 中的 `cpx_22138` 记录）；
2. **桌面查阅备份**（`C:\Users\Administrator\Desktop\22138.txt`，严格 UTF-8 无 BOM）；
3. **本地生效配置**（`C:\Users\Administrator\.codex\config.toml`）。

**三大核心参数法定标准**：
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
- `requires_openai_auth = true`：用于在保活模式下点亮前端 Team 登录态徽标；
- `experimental_bearer_token = "sk-cpa-cfa8cfc9c5e3caaa208b999a"`：用于底层请求短路官方鉴权，实际走私有网关。两者缺一不可。

### 第四道防线：NTFS 文件系统只读加锁技巧（可选终极防御）
若处于多人操作机台或极度担心某个未知第三方脚本强删 `auth.json`，可利用 Windows 原生文件属性对其施加只读保护：
```powershell
# 施加只读保护（防止任何普通文件删除）
Set-ItemProperty -LiteralPath "C:\Users\Administrator\.codex\auth.json" -Name IsReadOnly -Value $true

# 如需更新凭证时临时解锁
Set-ItemProperty -LiteralPath "C:\Users\Administrator\.codex\auth.json" -Name IsReadOnly -Value $false
```

---

## 6. 验证与实机验收成果 (Verification)

1. **设置持久化检验**：核验 `~/.cc-switch/settings.json`，`preserveCodexOfficialAuthOnSwitch` 稳定为 `true`；
2. **CPA 连通性与密钥验证**：
   使用 Node 原生 HTTP 携带 `sk-cpa-cfa8cfc9c5e3caaa208b999a` 向 `https://cpx.040926.xyz/v1/models` 发送请求，返回 **HTTP 200 OK**，成功解析 43 个模型池；
3. **实机界面验收**：
   在 CC Switch 激活 `cpx_22138` 的前提下，重启 Codex Desktop，**左下角清晰展示用户头像与 Team 登录标识，登录态完全回归**！
4. **一键自愈脚本实机检验**：
   运行 `pwsh -File D:\codex-troubleshooting\scripts\restore-and-verify-auth.ps1`，秒级输出全绿健康诊断，JWT 身份断言解析完整。

---

## 7. 避坑口诀与常驻红线

> **切莫盲猜登录丢，源码审查解烦忧。**  
> **保活开关必须开，凭据常驻免遭害。**  
> **多盘备份留后路，一键体检防脱钩。**  
> **密钥对准短路桥，控制数据两相宜。**
