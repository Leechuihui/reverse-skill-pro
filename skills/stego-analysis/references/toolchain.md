# stego toolchain — 工具对照与专项脚本

> 配合 `SKILL.md`。工具缺失先查 `tool-index.md`，再 bootstrap，不要现场猜安装命令。

## A. 图片隐写容器速查表

| 工具/格式 | 载体 | 提取命令 | 备注 |
|---|---|---|---|
| steghide | JPG/BMP/WAV/AU | `steghide extract -sf f.jpg -p <pwd>` | 无密码试空串；爆破用 stegseek |
| outguess | JPG | `outguess -r f.jpg out.txt` | 常配题目给的 key：`-k key` |
| jsteg | JPG | `jsteg reveal f.jpg out.txt` | 无密码 |
| F5 | JPG | java F5 extract | 统计攻击可检测 |
| zsteg | PNG/BMP | `zsteg -a f.png` | 先跑它；关注 b1,rgb,lsb,xy 类行 |
| LSB-Audio | WAV | python wave 低位 | 见 §C 脚本 |
| openstego | PNG/WAV | GUI / CLI | 需同版本 |
| camouflage | 任意 | 专用提取 | 文件尾部追加型 |

## B. PNG 结构修复脚本（宽高被改）

```python
#!/usr/bin/env python3
# png_fix_size.py — 爆破 IHDR 宽高使 CRC 匹配
import zlib, struct

data = bytearray(open("target.png", "rb").read())
ihdr_off = data.find(b"IHDR") + 4          # 宽高字段起点
orig_crc = struct.unpack(">I", data[ihdr_off+12:ihdr_off+16])[0]
for w in range(1, 4096):
    for h in range(1, 4096):
        seg = bytes(data[ihdr_off:ihdr_off+8]) + struct.pack(">II", w, h) + bytes(data[ihdr_off+8:ihdr_off+12])
        if zlib.crc32(seg) == orig_crc:
            data[ihdr_off:ihdr_off+8] = struct.pack(">II", w, h)
            open("fixed.png", "wb").write(bytes(data))
            print(f"fixed {w}x{h}"); raise SystemExit
print("no match")
```

## C. WAV LSB 提取脚本

```python
#!/usr/bin/env python3
# wav_lsb.py — 按样本低位拼比特流
import wave, numpy as np

w = wave.open("target.wav", "rb")
n = w.getnframes(); ch = w.getnchannels(); sw = w.getsampwidth()
raw = w.readframes(n)
samples = np.frombuffer(raw, dtype={1:np.int8,2:np.int16,4:np.int32}[sw])
bits = (samples & 1).astype(np.uint8)
# 每 8 bit 一字节，MSB first；输出前 512 字节预览
out = bytearray()
for i in range(0, len(bits) - 7, 8):
    byte = 0
    for b in bits[i:i+8]: byte = (byte << 1) | int(b)
    out.append(byte)
    if len(out) >= 512: break
print(bytes(out[:64]))
open("lsb_out.bin","wb").write(bytes(out))
```

## D. 其他载体对照

| 载体 | 检查点 | 工具 |
|---|---|---|
| GIF | 帧间隔时间序列、隐藏帧、调色板 | `identify -verbose`、exiftool `-FrameTime` |
| 视频 | 多余音轨/字幕轨、关键帧夹带 | ffprobe、ffmpeg `-map 0` 全导出 |
| PDF | 未渲染对象、JS、附件、图层 OCG | peepdf、pdfdetach、qpdf 展开 |
| Office | zip 内多余条目、宏、customXml | olevba、unzip 手检 |
| NTFS/文件系统 | ADS Alternate Stream | `dir /r`、`Get-Item -Stream *` |
| 网络 | ICMP payload、DNS TXT、TLS SNI 外带 | 衔接 protocol-reverse |

## E. Windows PowerShell 快速体检（无第三方依赖）

```powershell
$f = "C:\case\target.jpg"
$bytes = [IO.File]::ReadAllBytes($f)
"size=$($bytes.Length)"
$text = [Text.Encoding]::ASCII.GetString($bytes)
[regex]::Matches($text, '[\x20-\x7e]{6,}') | Select-Object -First 20 -ExpandProperty Value
# JPEG 尾部检查
$eoi = $text.LastIndexOf([char]0xFF) # 粗略；精确版按字节扫 \xFF\xD9
```

## F. Evidence 规范

```
E-stego-static       file/exiftool/binwalk/尾部字节数 输出全文
E-stego-tool-<n>     每个尝试过的工具+参数+结果（含失败）
E-stego-extract      成功提取：命令 + 提取物 sha256 + 内容摘要
E-stego-negative     判定无隐写的完整否定证据链
```

Finding 写法：`hidden payload ({type}, {size}) extracted from {carrier} via {method}; evidence E-stego-*`。
