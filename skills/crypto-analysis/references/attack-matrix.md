# crypto attack matrix — 特征 → 攻击 → 脚本

> 配合 `SKILL.md`。每条含：识别特征 / 前置条件 / 最小脚本 / 变体。

## 1. RSA 家族

### 1.1 共因数（GCD）
- **特征**：多把公钥 n 不同但可能共享素数（批量证书场景高发）
```python
from math import gcd
from Crypto.Util.number import long_to_bytes
p = gcd(n1, n2); q = n1 // p; d = pow(e, -1, (p-1)*(q-1))
print(long_to_bytes(pow(c, d, n1)))
```

### 1.2 小指数 e=3 无填充
- **特征**：e=3，明文 m < N^(1/3)，密文 c = m^3 可能未取模
```python
from gmpy2 import iroot
m, exact = iroot(c, 3)   # exact=True 直接开方成功
```
变体：广播攻击（Håstad）——同明文用 3 个不同 n 加密，CRT 合并后开立方。

### 1.3 共模攻击
- **特征**：同一 n、两个互质 e（如 e1=3, e2=65537），同明文两份密文
```python
def egcd(a, b):
    if b == 0: return (a, 1, 0)
    g, x, y = egcd(b, a % b); return (g, y, x - (a // b) * y)
g, s, t = egcd(e1, e2)
m = (pow(c1, s if s > 0 else -s, n) if False else None)
# 标准式：m = c1^s * c2^t mod n（s,t 为扩展欧几里得系数，负指数用逆元）
inv = lambda a: pow(a, -1, n)
m = (pow(c1, s, n) * pow(c2, t, n)) % n if s >= 0 and t >= 0 else \
    (pow(c1, s % phi, n) * pow(c2, t % phi, n)) % n
```

### 1.4 Wiener（大 d）
- **特征**：e 很大（接近 n）→ 暗示 d 小；连分数展开 e/n 收敛出 d
- 工具：`RsaCtfTool --attack wiener`

### 1.5 Coppersmith 已知高位/低位
- **特征**：已知 p 的一半以上比特（LSB 泄露、随机数缺陷）
- 工具：Sage `small_roots(f(x), X, beta)`；模板见 RsaCtfTool `coppersmith` 攻击族

### 1.6 低私钥指数泄露 / d 泄露部分比特
- 组合 Boneh-Durfee / 部分密钥恢复，均 Sage 化处理

## 2. 分组密码模式弱点

### 2.1 ECB 图像化 / 重排
- **特征**：识别三件套发现大量重复块
- ECB 模式下相同明文块 → 相同密文块；可做块级删除/重放。PNG/BMP 密文直接当图像渲染看轮廓。

### 2.2 CBC Bit-Flipping
- **特征**：CBC 解密 + 服务端只校验「特定字段」
- 原理：改 C[i] 会翻转 P[i+1] 对应位（P'[i+1] = D(C[i+1]) ⊕ C[i]⊕Δ）
```python
delta = bytes(a ^ b for a, b in zip(orig_plain_block, want_plain_block))
tampered = cipher[:16*idx] + xor(cipher[16*idx:16*idx+16], delta) + cipher[16*idx+16:]
```

### 2.3 Padding Oracle
- **特征**：服务端对 padding 错误 vs 业务错误有可区分响应（状态码/时延/长度）
- 逐字节从后往前恢复每块明文；现成：`padding-oracle` pip 包、PadBuster

### 2.4 IV 可预测 / 固定 IV
- 第一块等价 ECB；跨会话同 key 同 IV → 字典重放

## 3. 流密码与 PRNG

### 3.1 XOR 重复密钥
- **特征**：熵中等、周期性统计波动
```python
# 先重合指数估 keylen，再按列频率分析（keylen 列各自做单表替换）
```
已知明文片段（HTTP 头 "GET /"、"{"）直接异或出 key 片段并循环验证。

### 3.2 RC4 弱实现 / WEP 式 IV 重用
- 相同 key 多条流 → 两密文异或消掉 keystream 得 m1⊕m2，配 crib dragging。

### 3.3 PRNG 还原
| PRNG | 攻击 | 条件 |
|---|---|---|
| C `rand()` (glibc) | 观察输出反推 state（additive feedback） | 连续若干输出 |
| Mersenne Twister | 624 个连续 32 位输出即可完全恢复状态 | 未 twist 完 |
| `Math.random()` (V8) | z3 约束求解 state | ~2 个 double 输出 |
| `time()` 种子 | 时间窗爆破 | 已知大致生成时间 |

## 4. 哈希

### 4.1 长度扩展攻击
- **特征**：`MAC = H(secret || message)` 用 MD5/SHA1/SHA256
```python
# hashp / hash_extender
hash_extender --data "orig" --secret-length 16 --append "&admin=1" \
  --signature <mac> --format sha256
```

### 4.2 碰撞构造
- fastcoll（MD5）、sha1collider；用于伪造证书/文件签名场景的原理演示

## 5. 古典密码速查

| 密文特征 | 候选 | 工具 |
|---|---|---|
| 全字母、频率分布平移 | 凯撒/ROT13 | dcode brute |
| 全字母、频率分布置换 | 单表替换 | quipqiup 自动解 |
| 周期性 IC 波动 | 维吉尼亚 | Kasiski + IC 定 keylen |
| 数字成对 (a,b) | Playfair/Hill | 维度试探 |
| 栅格状重排 | 栅栏/列移位 | 移位穷举 + 可读性打分 |
| Base32/64 变体字符集 | 自定义字母表 | 频率对齐猜字母表 |

## 6. ECC 快速入口

- 曲线参数可疑（小阶/奇异曲线/supersingular）→ Smart's attack / MOV
- 同 k 重用（不同消息同 r）→ k = (h1-h2)/(s1-s2) mod n → 恢复私钥
- ECDSA nonce 偏差（部分比特泄露）→ 格攻击（Hidden Number Problem）

## 7. Evidence 规范

```
E-crypto-mat-sha256      输入材料哈希与来源路径
E-crypto-script          攻击脚本相对路径 + 运行命令
E-crypto-recovered       恢复结果（明文/私钥）摘要（敏感值脱敏存 case 内）
E-crypto-fail-list       尝试过但不成立的攻击清单（防重复劳动）
```
