# emulation cookbook — 补环境与反检测手册

> 配合 `SKILL.md`。原则：每个未实现符号都要么补、要么 patch、要么记录 Evidence 说明为何可以忽略。

## A. unidbg 高频 JNI 补环境模板

### A1. AbstractJni 常见 override

```java
@Override
public DvmObject<?> callStaticObjectMethod(BaseVM vm, DvmClass dvmClass, String signature, VarArg varArg) {
    switch (signature) {
        case "android/os/Build->MODEL:Ljava/lang/String;":
            return new StringObject(vm, "Pixel 6");
        case "com/example/Utils->getKey()Ljava/lang/String;":
            return new StringObject(vm, "static_key_from_jadx");
    }
    return super.callStaticObjectMethod(vm, dvmClass, signature, varArg);
}

@Override
public int getStaticIntField(BaseVM vm, DvmClass dvmClass, String signature) {
    if ("android/os/Build$VERSION->SDK_INT:I".equals(signature)) return 29;
    return super.getStaticIntField(vm, dvmClass, signature);
}
```

定位方法：报错栈里的 `signature` 字符串直接抄进 switch，返回值先用 jadx 看真机语义再定。

### A2. 文件系统映射（App 私有文件 / assets）

```java
emulator.getSyscallHandler().addIOResolver(new IOResolver() {
    @Override
    public FileResult resolve(Emulator emulator, String pathname, int oflags) {
        if (pathname.equals("/data/data/com.example/files/config.bin")) {
            return FileResult.success(new ByteArrayFileIO(oflags, pathname, realConfigBytes));
        }
        if (pathname.contains("/proc/self/maps")) {
            return FileResult.success(new ByteArrayFileIO(oflags, pathname, fakeMaps()));
        }
        return null; // 其他交给默认处理
    }
});
```

`fakeMaps()` 要点：包含 so 自身真实映射行，去掉可疑 hook 库（xposed/frida 关键词），否则触发反调试分支。

### A3. JNI_OnLoad 里动态注册拿不到时的两条路

1. 正常路径：`dm.callJNI_OnLoad(emulator)` 后 `vm.findClass` 即可解析 RegisterNatives 注册的方法
2. 注册被混淆/加密：先静态找 `JNI_OnLoad` 偏移直接用 `module.callFunction(emulator, offset)` 单独执行；或 hook `vm.resolveClass` 打印注册表

## B. Unicorn 裸函数调用模板

```python
from unicorn import *
from unicorn.arm64_const import *

CODE_BASE = 0x100000
STACK_BASE = 0x7F000000
STACK_SIZE = 0x100000

mu = Uc(UC_ARCH_ARM64, UC_MODE_ARM)
mu.mem_map(CODE_BASE, 0x100000)
mu.mem_map(STACK_BASE, STACK_SIZE)
with open("libtarget.so", "rb") as f:
    so = f.read()
# 按 ELF Program Header 把 PT_LOAD 段搬进内存（或直接整文件映射 + 重定位）
mu.mem_write(CODE_BASE, load_segment_bytes)

SP = STACK_BASE + STACK_SIZE - 0x1000
mu.reg_write(UC_ARM64_REG_SP, SP)
mu.reg_write(UC_ARM64_REG_X0, input_ptr)   # 参数按 AAPCS64 放寄存器
mu.reg_write(UC_ARM64_REG_X1, input_len)

def hook_invalid(uc, access, address, size, value, user_data):
    print(f"[missing map] addr={address:#x} pc={uc.reg_read(UC_ARM64_REG_PC):#x}")
    uc.emu_stop(); return False

mu.hook_add(UC_HOOK_MEM_UNMAPPED, hook_invalid)
try:
    mu.emu_start(func_offset | 1 if thumb else func_offset, CODE_BASE + 0x100000)
except UcError as e:
    print("stop:", e, "pc=", hex(mu.reg_read(UC_ARM64_REG_PC)))
```

适用判断：目标函数不调 libc/JNI、纯计算 → Unicorn 最快；一旦出现 `plt` 外部调用 → 升级 unidbg/Qiling。

## C. 反检测对抗速查

| 检测点 | 特征 | 对策 |
|---|---|---|
| 读 /proc/self/maps 找 frida/xposed | open+read maps | IOResolver 返回清洗版 maps |
| ptrace(PTRACE_TRACEME) 自反调试 | syscall ptrace | unidbg 默认不支持 ptrace 会抛错 → hook 直接返回 0 |
| 时间差检测 | gettimeofday/clock_gettime 两次差值 | hook 时钟返回固定/可控增量 |
| /proc/self/status TracerPid | 文件内容检查 | 同 A2 映射伪造 status |
| 检测调试端口/进程名 | socket/readdir | 返回空目录或拒绝连接 |
| 完整性自校验（CRC of .text） | 遍历自身代码段 | patch 校验函数入口直接 ret；或让 mem_write 后同步重算 CRC |

**顺序铁律**：先跑一次收集全部检测点清单，再一次性补齐，避免「补一个崩下一个」的循环。

## D. Qiling Windows PE 要点

- rootfs 用 `examples/rootfs/x8664_windows`，缺的 DLL 复制到 `Windows/System32`
- 未实现 API 报 `api_not_implemented`：在 `ql.os.set_api(name, hook)` 里按语义返回
- 注册表访问走 `ql.os.registry_manager` 预置键值

## E. Evidence 规范

```
E-env-001-maps-fake      fakeMaps 内容 sha256 + 生效位置（IOResolver 行号）
E-env-002-build-model    MODEL=Pixel 6 影响 sign 输出（对比实验：改值→输出变化）
E-call-sign-io           input=… output=… 与真机抓包一致（3 组回归样本）
E-patch-crc-ret          patch 偏移 0x1A2B0 ret，理由：完整性校验阻断模拟
```

Finding 写法：算法还原类结论必须附「输入→期望输出→模拟输出」三元组至少 2 组，否则标记 `E-insufficient-evidence`。
