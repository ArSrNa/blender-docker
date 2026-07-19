# Blender-docker

本镜像参考blender官方环境安装，预装Flamenco+Blender。

Blender版本为4.5.11，如需修改，请参考`.ide/Dockerfile`

# Flamenco使用（推荐）

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

## 使用脚本启动
在打开的code-server内，启动Terminal，默认已经进入到了`/bin/bash`

*注：由于blender官方python文档写得太烂，建议因blender脚本遇到问题时，前往[stackexchange](https://blender.stackexchange.com/)查找和交流*

- 将需要处理的`.blend`文件上传到工作区
- 修改`eevee_render.py`，请参考下一章节[渲染脚本设置](#渲染脚本设置)
````shell
# 使用eevee渲染
/usr/local/blender/blender -b /workspace/{.blend文件} -P /workspace/eevee_render.py
# 使用cycles渲染
/usr/local/blender/blender -b /workspace/{.blend文件} -P /workspace/cycles_render.py
````


# 接入ArRM集群渲染使用（弃用）

## 下载控制端（已默认下载）

请前往 [https://www.arsrna.cn/app/render/](https://www.arsrna.cn/app/render/)，根据系统类型下载对应控制端

目前本项目已经配置有了

- 集群渲染控制端 `./arrm/arrm_control`，并已完成配置
- 集群渲染从机端 `arrm_server`

可以直接从cnb同时启动实现webui控制渲染的效果

## 启动
已经在cnb中设置了启动自动打开的脚本，如果还未运行，请手动运行下列命令：
```bash
cd arrm
# 启动控制端
./arrm_control
# 启动从机端
./arrm_server
```

在PORT中，映射`4625`端口打开控制端，`3000`（默认）端口打开从机端，或根据`config.yaml`配置文件中的`port`进行修改。
![端口映射](image/port.png)

## ArRM使用教程

没写完，等会


# 渲染脚本设置

要注意，由于我使用了mmd插件，导致摄像机视角有问题，透视变成了正交，所以加入了一句**强行让视角转为透视**，如果没有出现问题，或者摄像机本身就是正交视角的，请注释这一部分。

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

# 一些话

自2026-8-1起，CNB取消GPU的免费额度，其实2025年就有计划要取消了，没想到坚持了一年多。这个仓库应该是CNB的GPU Tag上线以来第一个GPU实践，其次是ComfyUI。云原生ComfyUI让大家打开脑洞做出创新，让CNB这个平台在AI时代出圈爆火。

过去了两年，AI发展到了今天，传统手艺人手搓三维动画开始绝版，我也很久没有尝试再做动画了，上一次是2024，这个项目也就一直beta至今。

不过，玩法依然继续开发，也要感谢不知名大佬邀请我加入CNB公测，体验到CNB的强势动力。希望各位玩得开心！
