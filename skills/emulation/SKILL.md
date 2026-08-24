---
name: emulation
description: |
  Use when the task needs emulating or simulating code outside its native environment: unidbg for
  Android JNI/native-so function calls with Java bridging, Qiling/Unicorn for user-mode ELF/PE/ARM
  execution, hooking native functions during emulation, bypassing anti-emulation checks, restoring
  algorithm implementations (sign/encrypt) from .so files, or fuzzing native code via an emulator
  harness. Trigger keywords: unidbg, qiling, unicorn 模拟执行, emulate so/jni/native, 算法还原,
  sign 还原, native 算法, 模拟调用.
---

# emulation — unidbg / Qiling / Unicorn 模拟执行

把「跑不起来的代码」变成「可调用的函数」：Android so 的 JNI 方法、Linux/Windows 用户态二进制里的算法函数、固件里的解析逻辑。核心原则：**先最小化加载，再逐个补环境；每个未实现调用都要有 Evidence 记录**。

## ACTION REQUIRED（读完后立刻执行）

1. `NOW`: 读取 `../field-journal/precedent-reverse.md` — 确认操作在授权范围内
2. `NOW`: 判断目标形态 → 选引擎矩阵（unidbg / Qiling / Unicorn）
3. `NEXT`: 读取 `../tool-index.md` 确认 JDK + Maven（unidbg）、Python（qiling）可用；缺则 bootstrap
4. `NEXT`: 读 `references/emulation-cookbook.md` 对应场景模板（JNI 补环境 / PE 加载 / 反检测）
5. `ACT`: 先让目标函数「被调用到」（哪怕参数全错），再逐步修到输出正确

## 适用范围

- APK 的 `.so` 里签名/加密算法还原：不脱壳、不跑完整 App，直接模拟调用 JNI 函数拿输入输出对
- 静态分析卡住时的动态验证：OLLVM 混淆函数直接喂参数看行为
- 固件用户态程序跨架构执行（ARM/MIPS 固件 daemon 在 x86 主机跑起来）
- 配合 `fuzzing`：用模拟器当 harness 喂变异输入
- 反调试/反模拟对抗下的绕过补丁

不适用：需要真实 GPU/传感器/内核驱动的完整 App 行为（→ `apk-reverse` 动态路线）、iOS 侧（→ `mobile-reverse`）。

## 引擎选型矩阵

| 场景 | 首选 | 理由 |
|---|---|---|
| Android so + JNI 调用 | **unidbg**（Java） | 内置 Android 环境：JNIEnv、syscall、文件系统、内存管理全套假实现 |
| Linux ELF 用户态（跨架构） | **Qiling**（Python） | 完整用户态框架：rootfs、syscall 模拟、内置 hook API |
| Windows PE 用户态 | Qiling (PE 支持) / Speakeasy | PE 加载器 + 常见 DLL 假实现 |
| 裸函数/纯算法片段 | **Unicorn**（底层） | 只要 CPU 模拟，自己映射栈和代码段，最轻量 |
| iOS/objc | 不适用 | 转 `mobile-reverse` |

## 工作流（以 unidbg 还原 so 算法为例）

### 1. 最小可调用骨架

```java
public class TargetEmu extends AbstractJni {
    private final AndroidEmulator emulator;
    private final VM vm;
    private final Module module;

    public TargetEmu() {
        emulator = new AndroidEmulator.Builder(EmulatorBuilder.ARM64).build();
        Memory memory = emulator.getMemory();
        memory.setLibraryResolver(new AndroidResolver(23)); // sdk=23 常用起点
        vm = emulator.createDalvikVM();          // 无 apk 时可不传 apk 文件
        vm.setVerbose(true);                      // 打印每个未实现的 JNI/syscall
        DalvikModule dm = vm.loadLibrary(new File("libtarget.so"), true);
        dm.callJNI_OnLoad(emulator);              // 有注册 JNI_OnLoad 时必须调
        module = dm.getModule();
    }

    public String callSign(String input) {
        DvmClass cls = vm.resolveClass("com/example/Security");
        StringObject in = new StringObject(vm, input);
        // 方法名/签名从 jadx 静态结果抄（衔接 apk-reverse）
        Object ret = module.callJniMethodN(emulator, "sign(Ljava/lang/String;)Ljava/lang/String;", vm, cls, in);
        return ret == null ? null : ((StringObject) ret).getValue();
    }
}
```

### 2. 补环境循环（核心劳动量）

运行 → 看 `vm.setVerbose(true)` 输出的 `find _xxx failed` / `Unsupported` → 按 cookbook 对应模板补：

| 报错模式 | 处理 |
|---|---|
| `java.lang.UnsupportedOperationException: com/…/getXxx()` | 在 AbstractJni 子类里 override 该方法返回合理值 |
| syscall 未实现（open/ioctl） | 用 `emulator.getSyscallHandler().addIOResolver()` 映射虚拟文件 |
| `getenv("xxx")` 返回空导致分支异常 | `emulator.getBackend().emu_...` 前 patch 或 hook `getenv` 返回常量 |
| SO 内读 `/proc/self/maps` 反调试 | IOResolver 返回伪造 maps 内容（cookbook §C） |

**铁律**：每补一个环境点，追加一条 timeline 记录 + Evidence（`E-env-<n>-<符号>`），否则回溯时不知道哪个假值影响了输出。

### 3. 校验与固化

- 拿真机/抓包的真实输入输出对做回归：`assert emu.callSign(realInput).equals(realOutput)`
- 通过后生成独立 jar/HTTP 服务，供 `js-reverse` 重放链路直接调用
- 把「输入格式、关键偏移、补环境清单」沉淀进 field-journal

## Qiling 快速模板（ELF 跨架构）

```python
from qiling import Qiling

def hook_open(ql: Qiling):
    path = ql.os.fs_manager.read(ql.arch.regs.r0)  # ARM32 示例
    print(f"[open] {path}")
    ql.arch.regs.r0 = 0xFFFFFFFF  # 返回 -1 或按需伪造 fd

ql = Qiling(["rootfs/arm/bin/target"], "rootfs/arm")
ql.os.set_syscall("open", hook_open)
ql.run()
```

rootfs 来源：固件提取产物（衔接 `firmware-pentest`）或 Qiling 官方示例 rootfs。

## 与其他 skill 的衔接

| 场景 | 去 |
|---|---|
| 先要静态定位目标函数/偏移 | `ida-reverse` / `ghidra-reverse` |
| so 从 APK 里取、JNI 注册结构不明 | `apk-reverse` |
| 模拟器当 harness 做 fuzz | `fuzzing` |
| 固件里提取的 daemon | `firmware-pentest` |

## 红线

- 只模拟授权样本；不要把补好的环境用于绕过付费校验后分发破解产物
- unidbg 项目自带 GPL 组件时注意产物许可边界
