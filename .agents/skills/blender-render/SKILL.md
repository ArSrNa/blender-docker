---
name: blender-render
description: 用 Blender 渲染 .blend 工程并回传结果。当用户要求「渲染 / render / 出图 / 出动画 / 渲一帧 / 导出序列帧」，或提到 EEVEE、Cycles、采样、分辨率、帧范围等渲染参数时使用本 Skill。
---

# blender-render

把用户的渲染诉求翻译成 `scripts/render-npc/render.sh` 的参数并执行，最后把产物回传。

## 核心规则

1. **不要自己拼 `blender -b ...` 命令**，一律走封装脚本。它负责：引擎回退、GPU 探测、
   参数翻译、输出目录与报告，并把渲染错误统一暴露在 `RENDER_REPORT`。
2. **默认引擎**：不指定时用 EEVEE（走 GPU）；脚本探测到无 GPU 会自动回退 `CYCLES + CPU`。
   用户显式指定引擎/设备时**必须**尊重用户选择（脚本也不会再回退）。
3. **参数不确定就先查**：用户给的参数名（中文或英文）在下面「参数对照」里找不到时，
   按「查指令的三条路径」去查 bpy / 官方 CLI 文档，**不要编造** CLI 参数。
4. 渲染耗时可能很长（CPU 动辄几分钟到几十分钟）。**先小样验证，再出正式图**：
   用 `--res-percent 25 --samples 8` 快速试一帧，把样图发出来确认，再跑正式参数。

## 参数对照（自然语言 → CLI）

| 用户可能说 | CLI 参数 | 说明 |
|---|---|---|
| 用 eevee / 实时渲染 / 快一点 | `--engine eevee` | Blender 4.2+ 对应 `BLENDER_EEVEE_NEXT` |
| 用 cycles / 光追 / 画质好一点 | `--engine cycles` | |
| 用显卡 / GPU / CUDA / OptiX | `--device gpu` | 仅对 cycles 生效；eevee 本身走 GPU |
| 用 CPU / 不用显卡 | `--device cpu` | |
| 别用 eevee，回退 cycles | `--engine cycles --device cpu` | |
| 采样 N / 采样数 N / 质量高一点 | `--samples N` | eevee→`taa_render_samples`，cycles→`samples` |
| 1920x1080 / 4K / 竖屏 1080x1920 | `--resolution 1920x1080` | 4K 用 `3840x2160` |
| 一半分辨率 / 25% 分辨率 | `--res-percent 50` | |
| 只渲第 1 帧 | `--frame 1` | 默认就是 1 |
| 渲 1 到 24 帧 / 序列帧 | `--frame 1-24` | 也支持 `1,3,5` / `1..24` |
| full HD png / 出 JPEG | `--format PNG` / `--format JPEG` | 还支持 WEBP / OPEN_EXR / TIFF |
| 输出到 xxx 目录 | `--outdir /workspace/output/xxx` | |
| 用某个工程文件 | `--blend path/to/a.blend` | 路径相对仓库根目录 |
| 8 线程 / 限定核数 | `--threads 8` | |

组合示例：

```bash
# 无参数：默认 EEVEE(GPU)，无 GPU 自动回退 CYCLES/CPU，渲第 1 帧
bash scripts/render-npc/render.sh --blend test.blend

# 用户说「用 CPU 的 cycles，1920x1080，采样 64，渲 1~10 帧到 output/anim」
bash scripts/render-npc/render.sh --blend test.blend \
  --engine cycles --device cpu --resolution 1920x1080 --samples 64 \
  --frame 1-10 --outdir /workspace/output/anim
```

## 高级 / 超出 CLI 范围的参数

CLI 覆盖不到的 bpy 设置（世界环境光、色彩管理、降噪、胶片透明、输出色彩空间、
逐个对象可见性等），用 `--extra-json` 透传，键名与
`scripts/render-npc/blender_render.py` 的 payload 字段一致：

```bash
bash scripts/render-npc/render.sh --blend a.blend \
  --extra-json '{"samples": 32, "transparent": true}'
```

仍不够时，写一个临时 bpy 脚本放进 `--extra` 之外的路径：
用 `blender -b a.blend -P my_script.py` 的形式（但要自己设置输出路径与格式）。

## 查指令的三条路径

用户点名某个设置但不知道具体参数时，按序查证后再动手：

1. **本仓库现成脚本**：`scripts/render-npc/blender_render.py`（已封装的字段）、
   `gpu-setup/render.sh`（无头 EEVEE/GPU 的既有写法）、`eevee_render.py`（旧的示例）。
2. **Blender 官方 CLI 文档**（用户点名参考的那份）：
   - 命令行渲染：https://docs.blender.org/manual/zh-hans/dev/advanced/command_line/render.html
   - 命令行参数全表：https://docs.blender.org/manual/zh-hans/dev/advanced/command_line/arguments.html
   - 要查某个参数：`curl -s <上面链接>` 后 grep，**别凭记忆写**
   - 关键事实：`-E/--engine`、`-f/--render-frame`、`-s/-e`、`-o/--render-output`、
     `-F/--render-format`、`-t/--threads`、`--gpu-backend`、`--cycles-device`（注意
     Cycles 附加参数必须写在 `--` 之后）。
3. **本地 bpy 自省**（最权威，跟版本走）：

```bash
# 列出可用渲染引擎
blender -b a.blend --python-expr "import bpy;print([e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items])"
# 查某个属性的取值范围/含义
blender -b a.blend --python-expr "import bpy;print([e.identifier for e in bpy.types.CyclesRenderSettings.bl_rna.properties['device'].enum_items])"
# 查 blender 自身支持的 CLI 参数
blender --help
```

注意：Blender 4.x 起 `BLENDER_EEVEE` 改名为 `BLENDER_EEVEE_NEXT`，
`CYCLES` 是 addon 引擎、不出现在 engine enum 里但可以直接赋值并渲染。

## 执行后的回帖格式

渲染完成后按下面结构回复（`RENDER_REPORT` 里的字段直接引用）：

```
渲染完成 · 引擎 <engine_used> / 设备 <device_used>
分辨率 <resolution> · 格式 <format> · 帧 <frames>
产物：<文件名列表>
<附上图>
```

若 `device_used` 含 `llvmpipe` 或 `notes` 里提示缺 NVIDIA 图形栈，必须**显式告知用户
走的是 CPU 软件渲染**，并给出原因与修复命令 `bash gpu-setup/setup_gpu.sh`。

失败时贴 `RENDER_REPORT` 的 `error` 与 `render.log` 的关键片段。
