---
name: zaxd-loan-ijiami-flutter-gateway
description: 众安贷(com.zaxd.loan) 爱加密+Flutter+XCMS网关逆向：完整还原 AES 网关加密算法（硬编码IV+0x40填充），9种动态方案被反调试压制的完整教训，含 Frida17 API 断裂与 DenyList/Shamiko 模块隔离两大坑。
metadata:
  type: project
---

# 众安贷 com.zaxd.loan 逆向 (2026-08-24)

**目标**: Flutter 壳 + 爱加密(IJiami) 加固的贷款 App，目标是网关签名/加密算法。
**结果**: 静态侧全胜 — blutter 还原 1514 个 dart 文件，`XCMSGatewayHelper::encrypt @0x908b28` 完整还原；动态侧 9 种方案全部被压制。

## 核心发现（可直接复用）

1. **XCMS 网关加密**（luban_sdk_flutter）:
   - `AES(key).encryptBytes(utf8(json), iv)` + base64 去换行
   - IV 硬编码 `"1234567812345678"`
   - 填充非 PKCS7：`padLen=(16-(len&15))&15`，填充字节为 `'@'`(0x40)
   - key 来自原生 `getAppInfo` MethodChannel 下发的 accessKey（长度校验 Smi cmp #0x20 = **16 字符**，即 AES-128）
2. **请求结构**: `{apiKey, bizParam(密文), clientReqId, requestPlatform, tokenPlatform}` + header `x-za-tenant`
3. **三环境网关**: gateway.zxaxtech.com / -pre / -test

## 踩坑记录

**坑1: Frida 17 移除 `Module.findExportByName` 静态方法**
- 症状: 所有旧脚本报 "TypeError: not a function"
- 修复: `Process.getModuleByName(lib).getExportByName(name)` 或 `Module.getGlobalExportByName`
- 同类断裂: `Memory.readUtf8String` → 用 `ptr.readUtf8String()`

**坑2: Magisk DenyList + Shamiko = zygisk 模块全隔离**
- 症状: zygiskfrida 对 denylist 内应用完全不注入、无日志
- 关键: denylist 的本意就是 root 隐藏，Shamiko 会把模块一并隔离
- 修复: `magisk --denylist rm <pkg>` 后注入恢复

**坑3: PowerShell 5.1 `Set-Content -Encoding UTF8` 写 BOM**
- 症状: ZygiskFrida 报 "config is not a valid json file offset 0"
- 修复: `[IO.File]::WriteAllText($p,$s,(New-Object Text.UTF8Encoding($false)))`

**坑4: 锁屏状态下 am start 不真正启动应用**，且 monkey 不报错 — 先 WAKEUP+keyevent 82。

**坑5: 反复 force-stop 会触发应用快速自毁循环**（疑似爱加密持久化敌对标记），设备需重启恢复。

## 动态对抗结论（爱加密此版本）

| 手段 | 结果 |
|------|------|
| frida-server spawn/attach | 静默 syscall 自杀 |
| 改名+移位 gadget (listen/script) | 内存特征扫描识别，仍死 |
| zygisk 注入自定义 .so | ✅ 可存活（libzsec/libzautils） |
| maps 扫描隐藏 | 无意义——检测在内存特征层 |

**可行路径**: zygisk 注入极小 freestanding .so（zig cc `-target aarch64-linux-gnu -shared -nostdlib`，裸 svc 调用，零符号依赖）做内存补丁。注意：注入器走 xdl_open/dlopen，**不能有未解析符号**（dl_iterate_phdr 都会失败）；maps 全量读取用一次性 mmap 大缓冲复用。

**未完成**: accessKey 运行时提取（应用存活窗口不稳定）。候选: blutter_frida.js 地址级 hook（需先解决存活）、内存 dump 搜 IV 锚点邻近字符串。

Related: [[apk-reverse]], [[reverse-engineering]]
