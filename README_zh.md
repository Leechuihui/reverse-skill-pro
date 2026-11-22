<p align="center">
  <img src="reverse-skill-pro.png" alt="reverse-skill-pro" width="140" />
</p>

<h1 align="center">reverse-skill-pro</h1>
<h3 align="center">逆向工程 / 授权渗透测试 / 安全研究 —— AI Agent 技能路由包（增强版）</h3>

<p align="center">简体中文 | <a href="README.md">English</a></p>

<p align="center">AI 自动路由 · 按需自举工具链 · 自动进化经验库 · 一键分诊 · 并行编排</p>

<p align="center">
  <a href="VERSION"><img src="https://img.shields.io/badge/release-v2.0.0-blue" alt="release v2.0.0"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="license"></a>
  <a href="https://github.com/Leechuihui/reverse-skill-pro/actions/workflows/ci.yml"><img src="https://github.com/Leechuihui/reverse-skill-pro/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="#验证"><img src="https://img.shields.io/badge/routing%20benchmark-189%2F189-brightgreen" alt="benchmark"></a>
</p>

<br/>

<a id="关于"></a>

## 关于项目

当 AI Agent（Claude Code、Codex、Cursor、OpenCode 或其他兼容客户端）遇到 APK、二进制、前端 JS 加密、CTF 或渗透测试任务时，这套系统能让它先路由到正确的方法论，再调用本机工具执行，而不是盲目猜命令。

```text
用户任务 / 样本文件
  → RULES.md
  → MASTER-ROUTING / master-route.ps1（PRIMARY）
  → quick-triage.ps1（拿到文件时：魔数识别 → 类型路由 → 工具核对）
  → case-init / scope.md（授权 + network_profile；未就绪禁止对目标 ACT）
  → 目标 Skill → 工具 / MCP / 脚本
  → timeline + Evidence→Finding→Path → 报告 + field-journal
```

**解决三个痛点：**
- AI Agent 面对 APK、ELF、JS、PCAP 不知道该用 jadx 还是 Frida 还是 IDA
- 工具路径、MCP 服务、脚本入口分散在不同机器，迁移困难
- 同样的问题每次重新踩坑，经验无法复用

<a id="当前状态"></a>

## 当前状态

| 路由规则 | 回归基准 | 核心 Skill | CI 平台 | 客户端模型 |
|---:|---:|---:|---|---|
| 47 条（R0–R48） | 189 条用例 | 48 个已跟踪模块 | Windows + Ubuntu | 平台无关 |

PRIMARY 快路径：[skills/MASTER-ROUTING.md](skills/MASTER-ROUTING.md) · 全表：[skills/routing.md](skills/routing.md) · 作战契约：[skills/ops/](skills/ops/)

<br/>

<a id="pro-增强"></a>

## Pro 增强

| 增强项 | 内容 |
|--------|------|
| 新技能 R45 `fuzzing/` | AFL++/libFuzzer/honggfuzz/boofuzz/syzkaller 全链路：harness 模板、种子策略、崩溃分诊、ASan 解读 |
| 新技能 R46 `emulation/` | unidbg/Qiling/Unicorn 模拟执行：so/JNI 算法还原补环境闭环、反检测对抗速查 |
| 新技能 R47 `crypto-analysis/` | RSA/ECC/格攻击、padding oracle、古典密码、PRNG 还原、识别三件套 |
| 新技能 R48 `stego-analysis/` | 图片/音频/文档隐写五步体检与提取、PNG 宽高修复/WAV LSB 脚本 |
| 一键分诊 | `skills/scripts/quick-triage.ps1/.sh`：魔数识别→类型路由→工具核对→triage 报告 |
| case 断点续作 | `skills/scripts/case-resume.ps1/.sh`：auth 状态/timeline/workitems/evidence 恢复与下一步清单 |
| MCP 预置档案 | `skills/config/mcp-presets.json`：8 个常用安全 MCP 接线信息 + 客户端配置片段 |
| 并行编排模板 | `skills/references/parallel-orchestration.md`：RE 三路并行/侦察扇出/CTF 双线 |

<br/>

<a id="快速开始"></a>

## 快速开始

### 前置依赖

- **Java / JDK** — 运行 jadx、apktool
- **Node.js 22.12+** — JS 工具链和 MCP 服务
- **Python 3.x** — Frida 和辅助脚本
- **代码 AI 客户端** — Claude Code、Codex、Cursor、OpenCode 或其他兼容客户端

### 安装

```bash
git clone https://github.com/Leechuihui/reverse-skill-pro.git
```

### 初次使用

> 初次下载后，只需让 AI 阅读 [README_AI.md](README_AI.md)，即可按当前环境完成路由与工具检查。

各平台部署参考：
- **Kali Linux** → [kali/README-kali.md](kali/README-kali.md)
- **Ubuntu/Debian** → [docs/platforms/linux.md](docs/platforms/linux.md)
- **macOS** → [docs/platforms/macos.md](docs/platforms/macos.md)

<br/>

<a id="使用说明"></a>

## 使用说明

### 支持场景

| 场景 | 入口 |
|------|------|
| APK / Android 逆向 | `skills/apk-reverse/` |
| iOS / 移动端 | `skills/mobile-reverse/` |
| 二进制逆向 (exe/dll/so/elf) | `skills/ida-reverse/` / `skills/radare2/` |
| .NET / C# | `skills/dotnet-reverse/` |
| 前端 JS 签名 / 加密参数 | `skills/js-reverse/` |
| DSL VM / 风控自定义 VM | `skills/reverse-engineering/dsl-vm-reverse/` |
| HTTP 抓包 / 请求重放 | anything-analyzer、Reqable MCP + `js-reverse/` |
| 恶意软件 / YARA | `skills/malware-analysis/` |
| 渗透测试 / 漏洞扫描 | `skills/pentest-tools/` |
| 攻击链 / 红队编排 | `skills/attack-chain/` |
| Case 证据审查 / 报告交接 | `skills/case-review/` |
| CTF 竞赛 | `CTF-Sandbox-Orchestrator/`（42 个子技能） |
| 固件 / IoT | `skills/firmware-pentest/` |
| 补丁差分 / N-day | `skills/patch-diff-exploit/` |
| Pwn / 漏洞利用 | `skills/pwn-chain/` |
| EDR 绕过 | `skills/edr-bypass-re/` |
| API / GraphQL | `skills/api-security/` |
| 供应链 / SBOM | `skills/supply-chain-security/` |
| LLM / AI 安全 | `skills/llm-security/` |
| 模糊测试 | `skills/fuzzing/` |
| unidbg / Qiling 模拟执行 | `skills/emulation/` |
| 密码学分析攻击 | `skills/crypto-analysis/` |
| 隐写分析 | `skills/stego-analysis/` |
| OLLVM 脱密 | `skills/reverse-engineering/references/ollvm-deobfuscation.md` |
| 图表 / 报告 | `skills/diagram-generator/` / `skills/docs-generator/` |

### 关键文件

| 文件 | 用途 |
|------|------|
| [README_AI.md](README_AI.md) | AI Agent 配置引导（Agent 必读） |
| [RULES.md](RULES.md) | 全局路由规则 |
| [skills/MASTER-ROUTING.md](skills/MASTER-ROUTING.md) | PRIMARY 快路径 |
| [skills/routing.md](skills/routing.md) | 路由矩阵（场景 → Skill） |
| [skills/router.md](skills/router.md) | 总控入口（路由） |
| [skills/INDEX.md](skills/INDEX.md) | 自动生成的 Skill 导航索引 |
| [skills/config/routing.json](skills/config/routing.json) | 路由单一事实源（47 条规则，R0–R48） |
| [skills/config/mcp-presets.json](skills/config/mcp-presets.json) | MCP 预置接线档案 |
| [skills/tool-index.md](skills/tool-index.md) | 本机工具索引（自动生成） |
| [skills/scripts/master-route.ps1](skills/scripts/master-route.ps1) | 一键分诊（关键词路由） |
| [skills/scripts/quick-triage.ps1](skills/scripts/quick-triage.ps1) | 样本一键分诊（魔数 + 类型 + 工具） |
| [skills/scripts/case-init.ps1](skills/scripts/case-init.ps1) | 作战 case 目录（scope/timeline） |
| [skills/scripts/case-resume.ps1](skills/scripts/case-resume.ps1) | case 断点续作 |
| [skills/references/parallel-orchestration.md](skills/references/parallel-orchestration.md) | 并行子代理编排模板 |
| [skills/scripts/test-routing.ps1](skills/scripts/test-routing.ps1) | 189 条路由回归基准 |
| [skills/ops/](skills/ops/) | Scope / 证据链 / 角色 / 时间线 / skill 供应链安全 |

### 仓库结构

```text
.
├── README.md (English) / README_zh.md / README_AI.md
├── RULES.md / RULES_zh.md        # 全局路由（含 scope 门）
├── skills/
│   ├── MASTER-ROUTING.md         # PRIMARY 快路径
│   ├── SKILL.md / routing.md     # 总控 + 三轴矩阵
│   ├── ops/                      # Scope / 证据链 / 角色 / 时间线
│   ├── scripts/                  # master-route / quick-triage / case-init / case-resume / bootstrap
│   ├── config/                   # routing.json + mcp-presets.json
│   ├── references/               # 并行编排 / 社区 skill 对照
│   ├── field-journal/            # 脱敏经验
│   ├── fuzzing/ emulation/ crypto-analysis/ stego-analysis/   # pro 新增
│   └── ...（44 个领域技能）
├── CTF-Sandbox-Orchestrator/     # CTF 子技能
├── burp-mcp-full/                # Burp 扩展源码
├── docs/                         # 平台与架构
└── kali/                         # Kali 脚本
```

<br/>

<a id="许可证"></a>

## ⚖️ 许可证

本项目主体采用 **MIT License**（详见 [LICENSE](LICENSE)）。

**子模块与第三方依赖：**
- **CTF-Sandbox-Orchestrator/**：**GNU GPLv3**
- 其他工具（jadx、frida、nmap 等）遵循各自官方许可

## 免责声明

本项目仅限用于合法的安全研究、教育、CTF 竞赛，以及对自有系统或已获得明确授权的目标进行测试。

**严禁在未经授权的情况下访问、扫描、利用、干扰目标或获取数据。** 使用者须自行确保其行为符合适用法律法规及授权范围；因滥用本项目造成的任何损失或法律责任，均由使用者自行承担。
