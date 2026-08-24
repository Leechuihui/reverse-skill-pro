# fuzzing playbook — harness 模板与崩溃分诊手册

> 配合 `SKILL.md` 使用。所有模板先在本地冒烟 60 秒再放量。

## A. 常见格式解析库的种子策略

| 格式 | 必备种子 | max_len 建议 | 高频崩溃点 |
|---|---|---|---|
| PNG | 1x1、调色板图、interlaced | 16k | IDAT 长度、chunk 边界 |
| JPEG | 基线、渐进式、EXIF | 32k | MCU 解码越界 |
| ZIP | 空包、加密包、嵌套 | 64k | 中央目录偏移、解压炸弹（配 -m） |
| PDF | 单页、带 JS、带字体 | 128k | 字体解析、Xref 混淆 |
| XML | 命名空间、DTD、XXE 样式 | 32k | 实体展开（DoS）、编码声明 |
| PCAP | 各链路层各 1 个 | 8k/包 | 包头长度字段 |

## B. AFL++ 三种模式速查

```bash
# 源码插桩（最快，首选）
afl-clang-fast++ -fsanitize=address harness.cpp target.cpp -o target
afl-fuzz -i in -o out -- ./target @@

# QEMU 模式（闭源 ELF，无需源码）
afl-fuzz -i in -o out -Q -- ./target @@
# 提速：先用 afl-gotcpu 确认核心；-t 加大；配合 AFL_QEMU_PERSISTENT_ADDR 常驻循环

# Frida 模式（闭源 + 复杂依赖）
afl-fuzz -i in -o out -O -- ./target @@
```

持久模式模板（QEMU）：

```c
// 目标里找 main loop 或单次处理函数地址，传给 AFL_QEMU_PERSISTENT_ADDR
// AFL_QEMU_PERSISTENT_CNT=1000 每 1000 次迭代重置
```

## C. libFuzzer 特性开关

```bash
./fuzz_harness corpus \
  -dict=target.dict \
  -max_len=65536 \
  -timeout=5 \                # 单输入超时秒
  -rss_limit_mb=4096 \        # OOM 阈值
  -malloc_limit_mb=512 \      # 单次 malloc 上限
  -artifact_prefix=./artifacts/ \
  -jobs=8 -workers=8          # 多核
```

有价值组合：
- `-max_total_time=3600` 定时停
- `-focus_function=parse_header` 引导能量到热点函数（需数据流追踪编译 `-fsanitize=fuzzer-no-link`）
- `-entropic=1`（默认开）新覆盖加权

## D. ASan 回溯解读速查

| 报错头 | 含义 | 第一眼看哪帧 |
|---|---|---|
| heap-buffer-overflow | 堆越界读写 | WRITE/READ size 与调用栈最内层 memcpy/index |
| use-after-free | 释放后使用 | free 栈 vs alloc 栈对比 |
| stack-buffer-overflow | 栈数组越界 | 是否用户输入长度直接进栈拷贝 |
| SEGV on unknown address | 野指针 | 地址是否近似 null（0x00000000xxxx = 空指针解引用，低危） |
| allocation-size-too-big | 超大分配 | 长度字段未校验 → 可能可控 DoS |
| container-overflow | std::vector 越界 | size() vs capacity() 混用 |

去重键：`sanitizer 类型 + 顶部 3 帧（模块!函数）`。同键合并为一个 Finding。

## E. Windows / WinAFL 要点

```
DynamoRIO\bin64\drrun.exe -c winafl.dll -target_module target.dll ^
  -target_method fuzz_target -fuzz_iterations 1000 -nargs 2 --
  winafl_debug.exe input_file
```

- 先用 `winafl_debug.exe` 校验目标函数命中
- 崩溃检测靠 `AFL` 的管道退出码；建议同时挂 Application Verifier + 页堆（`gflags /p /enable target.exe /full`）

## F. syzkaller 最小上手

1. 编译内核：`CONFIG_KCOV=y CONFIG_DEBUG_INFO=y CONFIG_KASAN=y`
2. `syz-manager -config my.cfg`（配置 VM 镜像 + ssh key + workdir）
3. 新设备描述写进 `sys/linux/<driver>.txt` → `make generate` → `syz-extract`
4. 崩溃自动落 `workdir/crashes/`，用 `syz-repro -config my.cfg crash-log` 生成 C 复现器

## G. Evidence 命名规范（对齐 ops/evidence-finding-path.md）

```
E-crash-001-input    minimized.bin (sha256:…) repro: ./fuzz_harness minimized.bin
E-crash-001-asan     full sanitizer log paste
E-crash-001-dedup    key: heap-buffer-overflow @ mod!func_a+0x1c / mod!func_b / mod!main
E-cov-baseline       afl-whatsup 快照（edges found, corpus count）
```

Finding 模板一句话结构：`{crash type} in {function} reachable via {input path}, impact {crash/DoS/potential RCE}, evidence E-crash-001-*`。
