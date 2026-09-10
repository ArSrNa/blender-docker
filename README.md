# Blender-docker

本镜像参考blender官方环境安装，预装Flamenco+Blender以及GPU相关驱动。

Blender版本为4.5.11，如需修改，请参考`.ide/Dockerfile`

ArRM及详细参考文档：https://arsrna-it.feishu.cn/docx/CzGYdwx5ooI6pvxmaJQcNrqanud?from=from_copylink

# 已知问题（非常重要）

由于Blender4开始，Eevee渲染器使用了EGL，`glxinfo -B`、`vulkaninfo`最后得出的结论都是LLVMpipe，并不支持GPU加速，各种驱动已经尝试，经过91小时的折腾，各种驱动，各种镜像安装反复尝试，什么Workbuddy，Codebuddy各种buddy；OpenCode，ClaudeCode各种code；hy3，deepseek v4 pro，kimi 3各种2345模型；Fable5肥波痩波、五花波、曼波、半肥半瘦肥瘦相间波、正弦波余弦波方波锯齿波三角波各种波都跑过了，均无法解决。

2026-8-1 02:32更新，目前已有方法绕过来解决，但依然无法发挥最大性能，具体做了什么不知道，反正很复杂很复杂，烧了我1900多万token
![alt text](image/resolve-EGL.png)

当然，不保证下次进入容器就是解决的，只是在Claude Code运行的时候帮我改变容器环境之后问题得到解决，你也可以尝试手动运行 `./gpu-setup/setup_gpu.sh` 来运行。

**注意：每次启动环境后，需要预留6.9分钟等待驱动安装**，可以前往`云原生构建`，然后点开刚刚启动的`云原生开发`查看日志，如果安装GPU驱动这一个步骤绿色了，就完成了


# 接入ArRM集群渲染使用

## 下载控制端（已默认下载）

请前往 [https://www.arsrna.cn/app/render#download](https://www.arsrna.cn/app/render#download)，根据系统类型下载对应控制端

## 启动

自动运行：
```bash
./start-arrm.sh
```

或者手动分别运行下列命令
```bash
cd arrm
# 启动控制端
./arrm/arrm_control-linux &
# 启动从机端
./arrm/arrm_slave_linux &
```

在PORT中，映射`4625`端口打开控制端，`3000`（默认）端口打开从机端，或根据`config.yaml`配置文件中的`port`进行修改。
![端口映射](image/port.png)

具体使用方法参考：

- ArRM及详细参考文档：https://arsrna-it.feishu.cn/docx/CzGYdwx5ooI6pvxmaJQcNrqanud?from=from_copylink


# Flamenco使用

点击最大的云原生开发按钮，进入环境

之后会自动启动命令，如果没有启动，请右键文件侧栏，`Open in Integrated Terminal`，然后运行`./start.sh`

之后会出现一个弹窗，告诉你8080端口可以使用，Open in Browser即可，如果关了，则在`PORT`Tab下，找到8080，⌘+点击链接即可跳转到对应页面

![](image/9061f7ba-8b8e-4dc5-8c55-c1599e94bc8b.png)

点击右上角Addon，下载插件，在本地电脑Blender上，`编辑-首选项-插件`

在弹出的窗口中，下拉选择`从本地磁盘安装`，选择刚刚下载的.zip插件

![](image/91aa0e42-70cb-4f4c-904a-f59b809828c8.png)

展开插件，将刚刚在网页打开显示的地址输入进去

![](image/flamenco-addon-url.png)

在blender输出设置里，可以看到Flamenco的选项，按需设置即可。

Job Type一定要选择`Simple Blender Render`，然后设置帧数，把链接的按钮断开，即可自行设置。

![](image/flamenco-setting.png)

![](image/render.png)

最后点击`Submit to Flamenco`，等待上传完毕后网页就会看到任务。等待任务完毕即可。

![render-result](image/render-result.png)

# 在云原生开发中使用

首先Fork本仓库，适配自己的开发环境。

## 修改镜像适配blender
在`.ide/Dockerfile`修改`BLENDER_MAJOR`与`BLENDER_VERSION`，以便适配本地版本

本地版本可在blender内通过左上角`blender图标——关于`找到
![blender版本](image/blender_version.png)

## 启动

点击右上角云原生开发，直接启动
![alt text](image/start.png)

**注意：启动完毕后需要等待GPU驱动安装完毕**，可到云原生构建-云原生开发展开日志查看状态。

## 使用脚本启动
在打开的code-server内，启动Terminal，默认已经进入到了`/bin/bash`

*注：由于blender官方python文档写得太烂，建议因blender脚本遇到问题时，前往[stackexchange](https://blender.stackexchange.com/)查找和交流*

- 将需要处理的`.blend`文件上传到工作区
- 修改`eevee_render.py`，请参考下一章节[渲染脚本设置](#渲染脚本设置)


### 命令行渲染
````bash
# eevee渲染（60-120帧）
blender -b test.blend -o output/####.png --frame-start 60 --frame-end 120 -a
# eevee渲染（60-120帧）
blender -b test.blend -o output/####.png -E CYCLES --frame-start 60 --frame-end 120 -a -- --cycles-device CUDA
````

````bash
# eevee渲染（第1帧）
blender -b test.blend -o output/####.png -f 1
# eevee渲染（第1帧）
blender -b test.blend -o output/####.png -E CYCLES -f 1 -- --cycles-device CUDA
````

### 脚本渲染
````bash
# 脚本渲染-eevee
blender -b /workspace/{.blend文件} -P /workspace/eevee_render.py
# 脚本渲染-cycles
blender -b /workspace/{.blend文件} -P /workspace/cycles_render.py
````

# 渲染 NPC「render」

在 Issue / PR 评论里 `@arsrna/blender-docker(render)` 说一句需求，她就帮你把工程渲出来并把图贴回评论。

```
@arsrna/blender-docker(render) 用 cycles cpu 渲 test.blend 第 1 帧，1920x1080，采样 64
@arsrna/blender-docker(render) 渲染 test.blend 的 1~24 帧序列，出 JPEG
@arsrna/blender-docker(render) 渲一帧看看                      # 什么都不说 = EEVEE + 第1帧 + PNG
```

也可以在「代码 - 分支详情页 - 云原生构建 - 手动触发」里点「渲染工程」按钮，
填一句话需求触发，不用写评论（按钮定义见 `.cnb/web_trigger.yml`）。

## 引擎与设备策略

| 情况 | 实际使用 |
|---|---|
| 默认（未指定） | **EEVEE**（走 GPU，Blender 4.5 对应 `BLENDER_EEVEE_NEXT`） |
| 默认 + 探测不到 GPU | 自动回退 **CYCLES + CPU** |
| 用户指定 `cycles` / `gpu` / `cpu` | 完全按用户指定执行，不再自动回退 |
| EEVEE/GPU 渲染中途失败 | 未显式指定引擎时，自动回退 CYCLES/CPU 重试 |

GPU 探测逻辑在 `scripts/render-npc/probe_gpu.py`：检查 `/dev/nvidia*` + glvnd EGL NVIDIA vendor
+ Vulkan ICD，三路任一命中即认为有 GPU。

> 注意：容器若缺 NVIDIA 图形用户态库，EEVEE 会**静默回落到 CPU 软件渲染（llvmpipe）**，
> 也就是「看着成功但慢得离谱」。作业报告里的 `device_used` 会写成
> `cpu(llvmpipe · 缺 NVIDIA 图形栈)`，遇到这个跑一下 `bash gpu-setup/setup_gpu.sh` 即可修复。

## 渲染 CLI（不经过 NPC 也能用）

```bash
bash scripts/render-npc/render.sh --blend test.blend [参数]
```

| 参数 | 说明 |
|---|---|
| `--blend PATH` | 要渲染的 `.blend`（必填） |
| `--engine NAME` | `eevee` / `cycles` / `workbench` / `auto`（默认 auto=eevee） |
| `--device NAME` | `gpu` / `cpu` / `auto`（默认 auto；仅对 cycles 有意义） |
| `--samples N` | 采样数（eevee → `taa_render_samples`，cycles → `samples`） |
| `--resolution WxH` | 例如 `1920x1080`、`3840x2160` |
| `--res-percent N` | 分辨率百分比 1~100 |
| `--frame SPEC` | `1` / `1,3,5` / `1-24` / `1..24`（默认 1） |
| `--format FMT` | `PNG` / `JPEG` / `WEBP` / `OPEN_EXR` / `TIFF` |
| `--outdir DIR` | 输出目录（默认 `/workspace/output`） |
| `--scene NAME` `--camera NAME` `--threads N` | 场景 / 摄像机 / 线程 |
| `--extra-json '{...}'` | 透传额外 bpy 指令（键名见 `blender_render.py` payload） |
| `--no-fallback` | 有 GPU 但渲染失败时不回退 cycles |
| `--no-install` | 缺 blender 时不自动下载安装 |

示例：

```bash
# 默认：EEVEE(GPU)，无 GPU 自动回退 CYCLES/CPU，渲第 1 帧
bash scripts/render-npc/render.sh --blend test.blend

# 用户说「用 CPU 的 cycles，1920x1080，采样 64，渲 1~10 帧」
bash scripts/render-npc/render.sh --blend test.blend \
  --engine cycles --device cpu --resolution 1920x1080 --samples 64 \
  --frame 1-10 --outdir /workspace/output/anim
```

跑完会在输出目录留下 `render.log`、`render-request.json`，并在 stdout 末尾打印一行
机器可读的 `RENDER_REPORT=<json>`（引擎、设备、分辨率、格式、帧、产物清单），
NPC 就是靠这一行生成回帖的。

## 目录结构

```
.cnb/settings.yml       # NPC 角色「render」的人设与工作流程
.cnb.yml                # issue.comment@npc / pull_request.comment@npc 渲染流水线
.cnb/web_trigger.yml    # 「渲染工程」手动触发按钮
.cnb/skills/blender-render/SKILL.md    # NPC 技能：自然语言→CLI 参数、查指令的三条路径
.agents/skills/blender-render/SKILL.md # 同上（项目级 skills 目录，兼容 CodeBuddy）
scripts/render-npc/
  render.sh             # 渲染入口：探测 GPU、回退引擎、组装指令、汇总报告
  blender_render.py     # bpy 参数翻译器 + 渲染执行
  probe_gpu.py          # GPU 能力探测
```

## 自定义与排错

- 换个 NPC 名字：改 `.cnb/settings.yml` 里 `npc.roles[].name`（顶层 key 与角色名要一致）
- 想让渲染跑在别的镜像：改 `.cnb.yml` 里 `docker.image`
- 想用 CPU 节点跑（省钱、不在乎速度）：把 `runner.tags` 改成 `cnb:arch:amd64` 并加大 `cpus`
- 渲染很慢：先 `--res-percent 25 --samples 8` 出小样确认构图，再跑正式参数
- 报错排查：看输出目录的 `render.log`，以及 `RENDER_REPORT` 里的 `error` 字段


# 渲染脚本设置

要注意，由于我的项目使用了mmd插件，导致摄像机视角有问题，透视变成了正交，所以加入了一句**强行让视角转为透视**，如果没有出现问题，或者摄像机本身就是正交视角的，请注释这一部分。

````python
for obj in bpy.data.objects:
    # 检查对象是否为摄像机
    if obj.type == 'CAMERA':
        # 设置摄像机为透视视角
        obj.data.type = 'PERSP'
        print(f"摄像机 {obj.name} 已设置为透视视角。")
````

更多配置请参考`eevee_render.py`内的注释进行修改


# 已知问题
- [√] 使用mmd插件进行制作的摄像机，会自动变为正交视角，导致渲染结果不一致（4.0以后不会出现）
- [√] ~~4.2以后，Eevee渲染器无法正常调用GPU渲染，已知是CNB平台没有开放/dev和权限导致EGL的问题，且暂时无法修复。~~ 已修复：通过补装与宿主机内核模块同版本的 NVIDIA 用户态图形库（EGL/GLX/Vulkan），EEVEE 已能走 GPU，且已固化进 `.ide/Dockerfile` + `start.sh`，下次打开自动生效。详见上方「接下来话筒交给AI」章节。

# 一些话

自2026-8-1起，CNB取消GPU的免费额度，其实2025年就有计划要取消了，没想到坚持了一年多。这个仓库应该是CNB的GPU Tag上线以来第一个GPU实践，其次是ComfyUI。云原生ComfyUI让大家打开脑洞做出创新，让CNB这个平台在AI时代出圈爆火。

过去了两年，AI发展到了今天，传统手艺人手搓三维动画开始绝版，我也很久没有尝试再做动画了，上一次是2024，这个项目也就一直beta至今。

不过，玩法依然继续开发，也要感谢不知名大佬邀请我加入CNB公测，体验到CNB的强势动力。希望各位玩得开心！
