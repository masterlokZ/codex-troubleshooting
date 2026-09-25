 # Codex Troubleshooting & Case Studies
 
 Codex Desktop / CLI 疑难杂症、底层报错、非预期假性故障与实战排错知识库。
 
 收录在使用与深度定制 OpenAI Codex 系列工具（包括 Codex Desktop、app-server、CLIProxyAPI / CPA 网关整合、模型目录定制等）过程中遇到的典型坑点、根因剖析与标准规避方案。
 
 ---
 
 ## 案例目录 (Cases Index)
 
 | 编号 | 案例名称 | 影响范围 | 根因分类 | 状态 |
 | :--- | :--- | :--- | :--- | :--- |
 | **001** | [model_catalog_json 存在 UTF-8 BOM 导致假性“Unable to load sign-in requirements”](cases/001-model-catalog-utf8-bom-crash.md) | Codex Desktop 启动 / 登录检测 | 文本编码 / JSON 解析 | 已解决 |
 
 ---
 
 ## 常用排错脚本工具 (Scripts)
 
 - [`scripts/check-and-strip-bom.ps1`](scripts/check-and-strip-bom.ps1): 检查并一键剥离指定文件（或目录下所有 JSON 文件）的前导 UTF-8 BOM 头。
 
 ---
 
 ## 知识库维护原则
 
 1. **真实排错驱动**：每个案例均来自实机真实踩坑与现场排错，严谨记录混淆表象、底层取证、最小化修复与经验沉淀。
 2. **编码铁律**：本仓库中所有文件及所管理的配置文件**一律严格使用 UTF-8 无 BOM 格式**（UTF-8 without BOM）。
