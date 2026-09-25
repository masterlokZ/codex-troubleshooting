 # Case 001: model_catalog_json 存在 UTF-8 BOM 导致假性“Unable to load sign-in requirements”
 
 - **故障级别**：P1（阻塞客户端启动与登录初始化）
 - **涉及组件**：Codex Desktop、app-server、`model_catalog_json` 配置
 - **典型表象**：启动时卡在 `Loading sign-in requirements...`，最终报 `Unable to load sign-in requirements`
 - **真实根因**：JSON 包含 UTF-8 BOM 头（`0xEF 0xBB 0xBF`），导致 app-server 模型目录解析失败，前端将初始化异常泛化暴露为登录检查失败
 
 ---
 
 ## 1. 故障现象与混淆表象 (Symptoms & Misleading Signals)
 
 当定制或更新自定义模型目录 `1444-model-catalog.json` 后，重新拉起 Codex Desktop 或热重载客户端时，界面出现以下流程：
 
 ```text
 Loading sign-in requirements...
   ↓（持续加载数秒）
 Unable to load sign-in requirements
 ```
 
 ### 极具误导性的混淆表象
 - **直观感觉**：“账号掉登录了”、“OAuth 认证失败”、“网络代理/梯子炸了”、“CPA 接口挂了”或“Windows 沙盒权限不够”。
 - **常见无效排查弯路**：排查网络连通性、更换代理节点、重启 CPA 网关、清理系统证书甚至反复尝试重新登录，均无法解决。
 
 ---
 
 ## 2. 根因深度剖析 (Root Cause Analysis)
 
 经过底层十六进制与文件字节流比对，真实原因非常隐蔽且纯粹：
 
 ### (1) UTF-8 with BOM 前导字节注入
 在 Windows PowerShell 或部分编辑工具中，如果不显式指定无 BOM 编码细节，默认的 UTF-8 导出（如 .NET `[System.Text.Encoding]::UTF8` 或某些重定向）会在文件起始位置自动写入 3 个隐藏字节：
 
 ```text
 EF BB BF
 ```
 
 这导致文件虽然在普通文本编辑器中肉眼看起来完全正常：
 ```json
 {
   "models": [...]
 }
 ```
 但在实际底层字节流上等同于：
 ```text
 [0xEF, 0xBB, 0xBF]{
   "models": [...]
 }
 ```
 
 ### (2) app-server 初始化与错误上报机制
 1. Codex Desktop 在启动初始化阶段，会由底层 `app-server` 读取配置中指定的 `model_catalog_json` 路径；
 2. 读取逻辑直接将读取到的文件字节作为纯字符串送入标准 JSON 解析器；
 3. 解析器在遇到开头的非法隐藏字符 `0xEF 0xBB 0xBF` 时立即抛出语法解析异常（`SyntaxError: Unexpected token '﻿'`）；
 4. `model_catalog_json` 解析属于客户端初始化链路的刚性依赖。初始化异常被上层统一捕获后，前端没有细分并弹窗提示“模型 JSON 格式错误”，而是降级回退到统一的错误占位：**“Unable to load sign-in requirements”**。
 
 ---
 
 ## 3. 排查证据与数据对比 (Evidence & Verification)
 
 对故障文件与修复后文件的字节数及头数据进行严谨比对：
 
 ```text
 原故障文件大小：419656 bytes (前 3 字节为 EF-BB-BF)
 删除 BOM 后大小：419653 bytes (前 4 字节为 7B-0D-0A-20，即 "{\r\n ")
 
 JSON 业务内容：完全没改
 模型配置条目：完全没改
 文件名与路径：完全没改
 ```
 
 剥离这 3 个字节后，再次拉起 Codex Desktop，客户端秒级完成初始化并正常进入会话界面，故障瞬间消除。
 
 ---
 
 ## 4. 标准修复与规避指南 (Fix & Prevention)
 
 ### 一键修复命令 (PowerShell)
 如果已有 JSON 文件被误写为带有 BOM 格式，可在 PowerShell 7 中执行以下单行命令快速剥离：
 
 ```powershell
 $path = 'C:\Users\Administrator\Desktop\1444-model-catalog.json'
 $bytes = [System.IO.File]::ReadAllBytes($path)
 if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
     [System.IO.File]::WriteAllBytes($path, $bytes[3..($bytes.Length - 1)])
     Write-Host "成功剔除 BOM，文件已转为标准 UTF-8 无 BOM 格式！" -ForegroundColor Green
 } else {
     Write-Host "文件无 BOM，无需修改。" -ForegroundColor Cyan
 }
 ```
 
 ### 开发环境避坑防线 (Language Best Practices)
 
 - **PowerShell / .NET**：
   - ❌ 避免使用：`[System.Text.Encoding]::UTF8`（其静态属性默认会发出 BOM）。
   - ✅ 正确做法：使用 `[System.Text.UTF8Encoding]::new($false)`，或 pwsh 7 的 `Set-Content -Encoding utf8NoBOM`。
 - **Python**：
   - ❌ 避免使用：`encoding="utf-8-sig"`（写入时会强行附加 BOM）。
   - ✅ 正确做法：使用 `encoding="utf-8"`（标准无 BOM）。
 - **Node.js**：
   - ✅ `fs.writeFileSync(file, content, 'utf8')` 默认原生即为无 BOM。
 
 ---
 
 ## 5. 总结口诀
 
 > **模型目录千万条，无 BOM 格式第一条。**
 > **写入若带三字节，登录界面报全竭。**
