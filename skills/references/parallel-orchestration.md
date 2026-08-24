# parallel-orchestration — 多技能并行编排模板

> reverse-skill-pro 增强：当任务天然可拆分为互不依赖的分析面时，用并行子代理同时推进，最后按 Evidence 汇聚。**并行只用于只读分析面；任何对目标的主动操作（扫描/注入/爆破）必须串行且过 scope 门。**

## 何时并行 / 何时串行

| 判定 | 处理 |
|---|---|
| 多个只读分析（静态反编译 + 字符串/熵分析 + 元数据体检） | ✅ 并行，各出 Evidence |
| 一条依赖链（定位函数 → 补环境 → 验证算法） | ❌ 串行，前一步输出是后一步输入 |
| 对同一网络目标的多个探测 | ❌ 串行（避免触发防护/重复流量），统一由 lead 排队 |
| 多个不同样本的同类分诊 | ✅ 并行（每个子代理一个 case 或共享 case 分区） |

## 编排模式 A：RE 三路并行（最常用）

适用：拿到一个二进制/APK，需要快速建立全景。

```text
lead（你）
├── sub-agent S1: 静态面
│     skill: ida-reverse / ghidra-reverse / apk-reverse
│     输入: 样本路径
│     产出: E-static-<n>（函数清单、导入导出、关键字符串、可疑 API）
├── sub-agent S2: 结构面
│     skill: reverse-engineering（triage 章节）
│     产出: E-triage-<n>（壳/混淆判定、熵、编译器指纹、签名）
└── sub-agent S3: 环境面
      skill: tool-index 校验 + bootstrap
      产出: 工具可用性清单（写进 case workitems）
汇聚: lead 合并三份 Evidence → 决定动态分析路线 → 串行执行
```

## 编排模式 B：渗透侦察扇出

适用：授权范围内多资产侦察（scope 已 granted）。

```text
lead
├── S1: 资产 A 的被动信息收集（OSINT/证书透明度）→ threat-intelligence
├── S2: 资产 B 的版本指纹（仅 banner，不主动扫描）→ pentest-tools recon-pipeline
└── S3: 代码/依赖面审计 → code-audit / supply-chain-security
汇聚: lead 统一去重 → 按 attack-chain lifecycle-checklist 排攻击优先级
红线: 所有主动探测必须由 lead 串行发起并记录 timeline
```

## 编排模式 C：CTF 双线

```text
S1: crypto-analysis 攻击矩阵逐条试（RSA 特征 → 共模/小指数…）
S2: stego-analysis 五步体检（file/exiftool/binwalk/strings/尾部）
汇聚: 任一线提取出材料 → 交叉喂给另一线（如隐写提取物是 RSA 公钥）
```

## 子代理任务卡模板（发给每个 sub-agent）

```markdown
## Task
- skill: <skill-name>
- mode: read-only | gated-act   # gated-act 必须附 scope 引用
- inputs: <文件路径 / case 目录>
- MUST:
  1. 只产出 Evidence 文件（E-<域>-<序号>），不直接下结论
  2. 每个 Evidence 附 repro_command（可独立复跑）
  3. 不修改 case 内他人产物；timeline 由 lead 统一追加
- deliverable: Evidence 清单 + 一段 ≤5 行的状态摘要（decision_delta 格式）
```

## 汇聚协议（lead 收尾必做）

1. 合并所有 Evidence 到 `case/evidence/`（append-evidence.ps1 保持 ID 唯一性）
2. 写一条聚合 timeline：`decision_delta: [parallel_merge:<N>-agents]` + `carry_forward_refs` 指向各子摘要
3. 冲突结论处理：两个子代理结论矛盾时，以「有 repro_command 且可复跑」的一方为准；都不能复跑则标记 `E-insufficient-evidence`
4. 更新 workitems 状态后继续串行阶段

## 反模式（禁止）

- ❌ 并行子代理各自改 scope.md —— scope 只有 lead 可写
- ❌ 把「并行」当成跳过 auth 门的方式 —— gated-act 子任务必须先验证 scope
- ❌ 子代理直接写最终报告 —— 报告由 lead 在证据齐备后经 docs-generator 生成
