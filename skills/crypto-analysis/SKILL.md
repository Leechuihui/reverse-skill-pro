---
name: crypto-analysis
description: |
  Use when the task is analyzing or attacking cryptographic material: identifying ciphers and encodings,
  classical cipher decryption (Caesar/Vigenère/substitution), RSA attacks (small e, common modulus,
  Wiener, Coppersmith, factor reuse), lattice problems, padding oracle, hash length extension, ECB/CBC
  mode weaknesses, custom/weak PRNG recovery, or CTF crypto challenges. Trigger keywords: rsa, ecc,
  lattice, 格密码, 共模攻击, coppersmith, wiener, padding oracle, 维吉尼亚, 凯撒, 古典密码, 密码分析,
  cryptanalysis, hash 扩展, 解密算法.
---

# crypto-analysis — 密码学分析与攻击

从「一段看不懂的密文/密钥材料」到「识别算法 → 定位弱点 → 拿到明文/私钥」的闭环。核心原则：**先识别再攻击；先查实现误用，再啃数学难题**。现实中 90% 的突破口是误用（弱随机、重用 nonce、错误模式），不是算法本身。

## ACTION REQUIRED（读完后立刻执行）

1. `NOW`: 读取 `../field-journal/precedent-reverse.md` — 确认操作在授权范围内
2. `NOW`: 对目标做「识别三件套」：编码探测 → 熵/块结构观察 → magic 头扫描（见工作流第 1 步）
3. `NEXT`: 读 `references/attack-matrix.md` 找到对应攻击条目与现成脚本
4. `NEXT`: 检查 Python3 + `pycryptodome` / `sympy` / `sage`（可选）可用性（`../tool-index.md`）
5. `ACT`: 按矩阵执行最小验证脚本，产出 Evidence 后再扩大攻击面

## 适用范围

- CTF crypto 题（RSA/ECC/格/古典密码/自定义密码）
- 渗透中发现的加密流量/配置文件/硬编码密钥分析（衔接 `code-audit`）
- 协议逆向中遇到的「疑似加密」字段归因（衔接 `protocol-reverse`）
- 实现审计：ECB 模式、固定 IV、nonce 重用、`Math.random()` 当密钥源

不适用：JS 前端加密参数还原的工程链路（→ `js-reverse`）、二进制里定位算法函数（→ `ida-reverse` / `emulation`）。

## 工作流

### 1. 识别三件套（每次必做）

```python
# identify.py — 先跑这个再谈攻击
import collections, math, base64, binascii

data = open("target.bin", "rb").read()
print(f"len={len(data)}")

# a) 编码探测
for name, fn in [("b64", base64.b64decode), ("hex", bytes.fromhex)]:
    try:
        d = fn(data.strip()); print(name, "OK ->", d[:32]); break
    except Exception: pass

# b) 熵（接近 8 bit/byte = 加密或压缩；明显低 = 编码/明文/古典密码）
freq = collections.Counter(data)
ent = -sum(c/len(data) * math.log2(c/len(data)) for c in freq.values())
print(f"entropy={ent:.2f}")

# c) 分组特征：len % 8 == 0 或 % 16 == 0 → 块密码；重复 16 字节块多 → ECB 嫌疑
blocks = [data[i:i+16] for i in range(0, len(data)//16*16, 16)]
dup = len(blocks) - len(set(blocks))
print(f"16B-blocks={len(blocks)} duplicates={dup}")
```

判读：熵 ~7.9+ 且无重复块 → 现代密码/压缩；有重复块 → **ECB**；熵 4-6 → Base64/古典密码；能读一半 → 异或/替换。

### 2. 攻击路由（详见 references/attack-matrix.md）

| 观察到的特征 | 直接跳转 |
|---|---|
| n 可分解 / 多条公钥共享因子 | RSA-共因数 |
| e=3 且明文很短 | RSA-小指数开方 |
| 同 n 不同 e 的两组密文 | RSA-共模 |
| 已知部分明文高位 | Coppersmith |
| CBC + 可控解密错误提示 | Padding Oracle |
| 密文统计频率不均 | 古典密码 |
| 「随机」IV/密钥可预测 | PRNG 还原 |

### 3. 固化输出

- 每个「破解成功」必须附：输入材料 sha256、攻击脚本路径、恢复出的明文/密钥、可复现命令
- Finding 按 `ops/evidence-finding-path.md`：Evidence（脚本+数据）→ Finding（弱点名）→ Path（从哪拿到材料、影响什么）

## 快速工具箱

```bash
# RSA 一把梭（RsaCtfTool 覆盖 20+ 攻击自动尝试）
python3 RsaCtfTool.py --publickey key.pem --uncipherfile cipher.bin
# 因式分解（小 n）
python3 -c "from sympy import factorint; print(factorint(N))"
# yafu / cado-nfs 用于 >2^80 的 n
# 古典密码
#   https://www.dcode.fr 系列识别器；quipqiup.com 自动替换表求解
```

## 与其他 skill 的衔接

| 场景 | 去 |
|---|---|
| 密文来自抓包字段，需要还原调用链 | `protocol-reverse` / `js-reverse` |
| 算法在 so/app 里，要拿运行时密钥 | `emulation` / `apk-reverse` |
| 密码学实现缺陷在源码里 | `code-audit` |
| 隐写载体里的加密 payload | `stego-analysis` |

## 红线

- 只对授权材料做攻击；破解他人账号凭据/付费内容属违法
- 报告中披露弱密码学实现时附修复建议（换 GCM、随机 IV、标准库 PRNG）
