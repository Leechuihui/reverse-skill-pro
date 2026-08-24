---
name: fuzzing
description: |
  Use when the task is coverage-guided or protocol fuzzing: building AFL++/libFuzzer/honggfuzz harnesses,
  seeding corpora and dictionaries, minimizing crashes with fuzzbench/tmin, triaging sanitizer output
  (ASan/MSan/UBSan), fuzzing network protocols with boofuzz, kernel syscall fuzzing with syzkaller, or
  turning a crash into a reproducible PoC. Trigger keywords: fuzz, fuzzer, AFL++, libFuzzer, honggfuzz,
  boofuzz, syzkaller, corpus, seed, crash triage, sanitizer, ASan, OOM, 模糊测试, 灰盒, 变异.
---

# fuzzing — 引导式模糊测试全链路

从「拿到目标（二进制/库/协议/内核接口）」到「可复现的崩溃 PoC」的工程化闭环。核心原则：**先搭 harness 再谈变异，先有种子再谈覆盖，先能复现再谈利用**。

## ACTION REQUIRED（读完后立刻执行）

1. `NOW`: 读取 `../field-journal/precedent-reverse.md` — 确认操作在授权范围内
2. `NOW`: 判断目标类型 → 跳到「选型矩阵」确定 fuzzer 与 harness 形态
3. `NEXT`: 读取 `../tool-index.md`，确认 `afl-fuzz` / `afl-clang-fast` / `boofuzz` 可用；缺则 bootstrap，不要猜路径
4. `NEXT`: 读取 `references/fuzzing-playbook.md` 中对应目标的 harness 模板
5. `ACT`: 先写最小可编译 harness + 3 个手工种子，跑通 1 分钟冒烟，再放量

## 适用范围

- 给闭源/开源二进制、解析库（图片/压缩包/字体/音视频）做覆盖率引导模糊测试
- 对自定义网络协议、固件 daemon 做协议模糊测试（boofuzz）
- 内核 syscalls / 驱动 ioctl 的 syzkaller 式模糊
- 崩溃去重、最小化、ASan 栈回溯解读、转成 exploit 输入（衔接 `pwn-chain`）

不适用：纯 Web 参数爆破（→ `pentest-tools`）、已定位漏洞后的利用链构造（→ `pwn-chain`）。

## 选型矩阵

| 目标形态 | 首选 | 备选 | 关键点 |
|---|---|---|---|
| 有源码 C/C++ 库 | libFuzzer + ASan/UBSan | AFL++ LTO 模式 | `-fsanitize=fuzzer,address`；种子入 `corpus/` |
| 闭源二进制（ELF/PE） | AFL++ QEMU 模式 (`-Q`) | Frida 模式 (`-O`) / honggfuzz | 无需源码；速度慢 2-5x，先用小超时 |
| Android native so | AFL++ + Frida-gum harness | unidbg 批量喂输入（→ `emulation`） | JNI 边界用模拟执行喂参 |
| 固件 daemon / 协议 | boofuzz 会话树 | AFL++ 截断重放 pcap 种子 | 先 `protocol-reverse` 还原报文结构 |
| Windows 闭源 | WinAFL (DynamoRIO) | honggfuzz | 目标函数偏移 + `-fuzz_iterations` |
| 内核 syscalls | syzkaller + syzlang 描述 | kAFL | 需要 VM + 内核带 KCOV |
| Go/Rust | go-fuzz / cargo-fuzz | AFL++ | Rust 必配 `-Zsanitizer=address` |

## 工作流（闭环五步）

### 1. Harness 构建（决定成败的一步）

```c
// libFuzzer 最小 harness：fuzz_harness.c
#include <stdint.h>
#include <stddef.h>
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    // 只调用一个稳定入口；禁止在 harness 里 free 用户数据后继续用
    target_parse(data, size);   // 替换成目标入口函数
    return 0;
}
```

```bash
# 编译（有源码）
clang -g -O1 -fsanitize=fuzzer,address,fuzzer-no-link -I include \
      fuzz_harness.c src/target.c -o fuzz_harness
# 冒烟：3 个种子跑 60 秒
mkdir -p corpus artifacts && cp seeds/* corpus/
./fuzz_harness corpus -max_total_time=60 -artifact_prefix=artifacts/
```

**Harness 自检清单（缺一不可）：**
- [ ] 同一输入重复调用两次行为一致（无全局状态污染），否则加 `-runs=1` 或每次重建上下文
- [ ] 输入长度边界处理（0 字节、超大输入 `-max_len`）
- [ ] 不把 stderr 刷屏（日志会拖慢 10x+）

### 2. 种子与字典

- 种子来源：样本自带测试文件、`protocol-reverse` 抓到的真实报文、格式文档里的合法样例
- 每类结构至少 1 个种子；嵌套格式（如 zip 内嵌 png）给「组合种子」
- 字典：从二进制抽高频 magic/字段名：`strings -n 4 target | sort -u > target.dict`
- AFL++ 用 `-x target.dict`，libFuzzer 用 `-dict=target.dict`

### 3. 放量运行

```bash
# 多核：主实例 + N 从实例
afl-fuzz -i corpus -o out -x target.dict -M m0 -- ./target @@
afl-fuzz -i corpus -o out -S s1 -- ./target @@
afl-fuzz -i corpus -o out -S s2 -Q -- ./target @@   # QEMU 模式（闭源）
# 监控
afl-whatsup -s out/
```

关键参数速查：`-t 200+`（超时 ms，慢目标加大）、`-m none`（内存不限，ASan 下必配或按 ASan 预算）、`-max_len`（按格式上限，如 PNG 建议 8k-64k）。

### 4. 崩溃分诊（Evidence 起点）

```bash
# 最小化崩溃输入
afl-tmin -i out/default/crashes/id:000000 -o minimized.bin -- ./target @@
# 单独复现并拿 ASan 栈
ASAN_OPTIONS=detect_leaks=0 ./fuzz_harness minimized.bin
```

每个崩溃必须产出 Evidence（走 `ops/evidence-finding-path.md`）：
- `E-crash-<N>-input`：最小化输入文件 + sha256
- `E-crash-<N>-asan`：完整 ASan 回溯（heap-buffer-overflow / use-after-free / stack-overflow…）
- `E-crash-<N>-dedup`：按「sanitizer 类型 + 栈顶 3 帧」去重结果

常见误报排除：OOM/超时不是漏洞（除非可控触发 DoS 在 scope 内）；栈溢出在深递归解析器里先看是否可达用户输入。

### 5. 转化与交接

- 可控性判断：崩溃点写入的数据是否来自输入？回溯里找 `memcpy/strcpy/read` 类传播帧
- 可利用 → 交接 `pwn-chain`（附 E-crash 系列 Evidence）
- 仅 DoS/健壮性问题 → 记 Finding，进报告（`docs-generator`）

## 协议模糊（boofuzz 快速模板）

```python
from boofuzz import *
sess = Session(target=Target(connection=TCPSocketConnection("127.0.0.1", 9999)))
s_initialize("req")
s_string("USER", name="cmd")
s_delim(" ")
s_string("anon", name="user")
s_static("\r\n")
sess.connect(s_get("req"))
sess.fuzz()
```

前置：用 `protocol-reverse` 先还原字段结构，把「长度字段」标成 `s_size()`，把「校验和」做成回调，否则变异全被服务端丢弃。

## 与其他 skill 的衔接

| 场景 | 去 |
|---|---|
| 闭源 so 无法直接 fuzz，需要喂 JNI 参数 | `emulation`（unidbg/Qiling 当 harness） |
| 崩溃要变成 ROP/堆利用 | `pwn-chain` |
| 协议结构未知 | `protocol-reverse` |
| 补丁比对找攻击面收敛点 | `patch-diff-exploit` |

## 红线

- 只对授权目标 fuzz（scope.md `auth.status = granted`）；对生产目标高并发变异等同拒绝服务攻击
- 内核 fuzz 必须在快照 VM 内，先拍快照再开跑
