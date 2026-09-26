 # Codex Troubleshooting & Case Studies
 
 Codex Desktop / CLI 疑难杂症、底层报错、非预期假性故障与实战排错知识库。
 
 收录在使用与深度定制 OpenAI Codex 系列工具（包括 Codex Desktop、app-server、CLIProxyAPI / CPA 网关整合、模型目录定制等）过程中遇到的典型坑点、根因剖析与标准规避方案。
 
 ---
 
 ## 案例目录 (Cases Index)
 
 | 编号 | 案例名称 | 影响范围 | 根因分类 | 状态 |
 | :--- | :--- | :--- | :--- | :--- |
| **001** | [model_catalog_json 存在 UTF-8 BOM 导致假性“Unable to load sign-in requirements”](cases/001-model-catalog-utf8-bom-crash.md) | Codex Desktop 启动 / 登录检测 | 文本编码 / JSON 解析 | 已解决 |
| **002** | [Windows 环境下执行 Git 触网命令被 GCM 劫持弹出 GUI 对话框卡死](cases/002-windows-git-credential-manager-popup.md) | 自动化 Agent / CLI 执行环境 / Git 触网 | Git 凭据机制 / Win32 进程隔离 | 已解决 |
| **003** | [Codex 混合登录态（官方 auth.json + 自建 CPA 网关）实现全功能原生体验与流量自主可控](cases/003-codex-hybrid-auth-cpa-architecture.md) | 客户端功能矩阵 / 模型路由 / 速率档位 | 架构双轨解耦 / 状态机判定 | 最佳实践 |
| **004** | [Windows 双层代理与 GeoFiles 智能分流网络环境配置与极速复原指南](cases/004-windows-dual-proxy-network-environment.md) | 网络基础设施 / 官方鉴权自动续期 / CPA 通信 | 代理链路 / 规则路由 / 双保险机制 | 最佳实践 |
| **005** | [Codex Desktop 版本升级路径失效与 CC Switch 多版本配置档案热备切换实战](cases/005-codex-version-upgrade-and-cc-switch-profile-management.md) | 版本升级热修 / CUA 路径对齐 / CC Switch 档案切换 | 路径死链排查 / 档案管理设计 / 零风险回退 | 最佳实践 |
| **006** | [CC Switch 双重工作模式（配置同步器 vs 15721 本地路由接管）深度解耦与防死循环避坑指南](cases/006-cc-switch-config-sync-and-local-proxy-takeover.md) | CC Switch 供应商配置 / 15721 本地代理 / 请求路由 | 架构分层解耦 / 死循环雪崩防御 | 最佳实践 |

---
 
 ## 常用排错脚本工具 (Scripts)
 
 - [`scripts/check-and-strip-bom.ps1`](scripts/check-and-strip-bom.ps1): 检查并一键剥离指定文件（或目录下所有 JSON 文件）的前导 UTF-8 BOM 头。
 
 ---
 
 ## 知识库维护原则
 
 1. **真实排错驱动**：每个案例均来自实机真实踩坑与现场排错，严谨记录混淆表象、底层取证、最小化修复与经验沉淀。
 2. **编码铁律**：本仓库中所有文件及所管理的配置文件**一律严格使用 UTF-8 无 BOM 格式**（UTF-8 without BOM）。
