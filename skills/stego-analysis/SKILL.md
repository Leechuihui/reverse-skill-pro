---
name: stego-analysis
description: |
  Use when the task is detecting or extracting hidden data from media and documents: LSB steganography
  in images, metadata/EXIF concealment, appended trailers after EOF, palette/alpha channel tricks,
  audio spectrogram payloads, video frame injection, PDF/Office document concealment, or password-
  protected stego containers (steghide/stegseek). Trigger keywords: steghide, zsteg, stegsolve,
  stegseek, 隐写, lsb, 盲水印, watermark, 图片隐写, 音频隐写, 文档隐写.
---

# stego-analysis — 隐写检测与提取

从「一张图/一段音频/一个文档」里找出并取出隐藏数据。核心原则：**先无损取证（元数据、结构、尾部），再变换域分析（LSB、频域、通道），最后才是密码爆破**。顺序错了会浪费大量时间。

## ACTION REQUIRED（读完后立刻执行）

1. `NOW`: 读取 `../field-journal/precedent-reverse.md` — 确认操作在授权范围内
2. `NOW`: 对目标跑「五步静态体检」（见工作流第 1 步），产出文件类型/尾部/元数据 Evidence
3. `NEXT`: 按载体类型跳转对应章节（图片 §A / 音频 §B / 文档 §C）
4. `NEXT`: 检查工具可用性（`../tool-index.md`）：`zsteg` / `stegsolve` / `binwalk` / `exiftool`
5. `ACT`: 发现加密容器才进入爆破分支（stegseek + rockyou），先记录已试清单

## 适用范围

- CTF Misc 隐写题（图片/音频/视频/文档）
- 应急响应中检查可疑媒体文件是否夹带数据（衔接 `digital-forensics`）
- 数据外泄检测：DLP 场景下判断图片是否被用于夹带

不适用：媒体文件本身是恶意载荷解析（→ `malware-analysis`）、隐写算法的逆向实现（→ `reverse-engineering`）。

## 工作流

### 1. 五步静态体检（所有载体通用，必做）

```bash
# a) 真实类型（扩展名不可信）
file target.*
# b) 元数据
exiftool -a -u -g1 target.jpg        # -a 显示重复标签，-u 未知名，-g1 分组
# c) 结构完整性 + 尾部附加数据
binwalk target.jpg                    # 嵌入文件签名扫描
python3 - <<'EOF'
data = open("target.jpg","rb").read()
eoi = data.rfind(b"\xff\xd9")         # JPEG EOI
print(f"size={len(data)} eoi_at={eoi} trailing={len(data)-eoi-2} bytes")
EOF
# d) 字符串速览（密码提示常藏这里）
strings -n 6 target.* | head -50
# e) 与原始/同类文件比对大小（异常膨胀 = 夹带嫌疑）
```

**Evidence**：`E-stego-static` 记录 file/exiftool/binwalk 输出与尾部字节数。

### 2. 按载体深入

#### §A 图片

```bash
# PNG/JPG LSB 多通道自动扫（PNG 最常用）
zsteg -a target.png                   # 全通道全序扫描；-v 看内容预览
# JPG DCT 系数域
stegdetect target.jpg                 # jsteg/outguess/F5 概率判断
stegseek target.jpg wordlist.txt      # steghide 密码爆破（无字典=rockyou 默认）
# 交互式位平面观察（GUI，WSB 下用 X11 转发或截图分析）
java -jar stegsolve.jar               # Analyze > Data Extract / Frame Browser
```

人工检查点：
- **调色板图（GIF/PNG-8）**：palette 顺序异常 = 调色板隐写；帧间隔时间序列藏 ASCII（GIF）
- **透明通道**：alpha 全 0/255 之外的规律值 → alpha LSB
- **尺寸 vs 像素数不一致**：IDAT/IHDR 被改 → 改回真实宽高（CRC 爆破脚本见 references/toolchain.md）
- **JPEG 尾部 EOI 后数据**：直接 carve 出来单独分析

#### §B 音频

```bash
# 频谱图看图（最常见套路）
python3 -c "import scipy.io.wavfile as w; print(w.read('target.wav')[0].shape)"
sox target.wav -n spectrogram -o spec.png    # 打开 spec.png 看
# LSB（WAV 无损格式）
zsteg 不适用 → 用 python wave 模块逐样本低位提取
# Morse / SSTV / DTMF
#   SSTV: sstv 解码器; DTMF: multimon-ng; Morse: 听/频谱
```

#### §C 文档

```bash
# PDF：对象流、JS、附件、未显示图层
pdfid target.pdf ; peepdf -i target.pdf       # JS/动作对象
binwalk target.pdf                             # 附件与嵌入文件
qpdf --qdf --object-streams=disable target.pdf out.pdf   # 展开压缩流再 grep
# Office (docx/xlsx)：本质 zip
unzip -l target.docx                           # 多余条目 / settings.xml 可疑宏
olevba target.doc                              # VBA 宏分析（衔接 malware-analysis）
```

### 3. 加密容器分支（最后手段）

1. 先收集密码候选：strings、exiftool 注释、题目描述关键词、文件名本身
2. `stegseek --crack target.jpg rockyou.txt`（比 hashcat 快千倍级，专攻 steghide）
3. 其他容器对照表见 references/toolchain.md §D
4. 每次失败记录到 timeline，避免重复跑同一字典

### 4. 固化输出

- 提取成功：Evidence 附「原始文件 sha256 + 所用命令 + 提取物 sha256」
- 判定无隐写：附五步体检全部输出作为否定证据（`E-stego-negative`），不要只说「没找到」

## 与其他 skill 的衔接

| 场景 | 去 |
|---|---|
| 提取物是加密数据 | `crypto-analysis` |
| 提取物是可执行/宏 | `malware-analysis` |
| 大批量媒体文件的自动化筛查 | `fuzzing` 思路做批处理 harness 或自写脚本 |
| 取证时间线整合 | `digital-forensics` |

## 红线

- 只分析授权材料；对他人发布的图像做隐写提取前确认用途合法
