# FROM nvidia/cudagl:11.4.2-base-ubuntu20.04
# FROM docker.cnb.cool/examples/language/cuda-12.4
FROM nvcr.io/nvidia/cuda:12.4.0-runtime-ubuntu22.04

# 修改镜像源
RUN sed -i 's/archive.ubuntu.com/mirrors.tencent.com/g' /etc/apt/sources.list && \
	sed -i 's/security.ubuntu.com/mirrors.tencent.com/g' /etc/apt/sources.list && \
	sed -i 's/cn.archive.ubuntu.com/mirrors.tencent.com/g' /etc/apt/sources.list

# 设置时区
# RUN export DEBIAN_FRONTEND=noninteractive && \
# ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
# echo "Asia/Shanghai" > /etc/timezone

ARG BLENDER_MAJOR=4.5
ARG BLENDER_VERSION=4.5.11
ENV BLENDER_TAR_URL=https://mirrors.aliyun.com/blender/release/Blender${BLENDER_MAJOR}/blender-${BLENDER_VERSION}-linux-x64.tar.xz

# 4.5以上需要Vulkan
RUN apt-get update && \
	apt-get install -y \
	curl wget nano git git-lfs unzip openssh-server ffmpeg \
	bzip2 libfreetype6 \
	libglu1-mesa \
	libxi6 libxrender1 libxkbcommon0 \
	libsm6 libxext6 libxcursor1 libxinerama1 libgl1-mesa-dev libgl1-mesa-glx libgl1-mesa-dri libegl1 \
	libglvnd0 libglx0 kmod libatomic1 \
	xz-utils htop axel vulkan-tools libvulkan1 libvulkan-dev mesa-vulkan-drivers mesa-utils-extra

#VNC环境
# RUN apt install x11vnc xvfb dbus-x11 kde-standard novnc dbus-x11 && \
# ENV VNC_PASSWORD cnb666

# Vulkan 相关环境变量
ENV VK_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json
ENV VK_LAYER_PATH=/usr/share/vulkan/explicit_layer.d
ENV VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation
# 无头 EGL 需要一个可写的 XDG_RUNTIME_DIR
ENV XDG_RUNTIME_DIR=/tmp/xdg

# ---------------------------------------------------------------------------
# NVIDIA 用户态图形栈（EGL/GLX/Vulkan/OptiX）——让无头 EEVEE 走 GPU 而非 CPU。
# 基础镜像 cuda:*-runtime 只带计算栈，缺图形用户态库；且用户态库版本必须与宿主机
# 内核模块精确匹配。
#
# 构建时直接把仓库里预下载好的 NVIDIA-Linux-x86_64-<VER>.run COPY 进镜像，只装
# 用户态库（--no-kernel-module，绝不碰内核）。这样打开环境不必再联网下载安装器，
# 秒级就绪。版本由 ARG NVIDIA_DRIVER_VERSION 控制，默认与当前宿主机 580.95.05 一致，
# 务必与宿主机的 nvidia-smi 驱动版本保持一致（见 gpu-setup/ 下的 .run 文件名）。
#
# 若宿主机驱动日后升级导致版本不匹配，运行时 start.sh / .ide/nvidia-graphics-setup.sh
# 仍会按真实版本自愈校正，本步骤只是让“常见版本”开箱即用。
ARG NVIDIA_DRIVER_VERSION=580.178.04
ENV NVIDIA_DRIVER_VERSION=${NVIDIA_DRIVER_VERSION}

COPY gpu-setup/NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run /opt/nvidia-installers/NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run

RUN export PATH="$PATH:/usr/sbin:/sbin" && \
	chmod +x /opt/nvidia-installers/NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run && \
	sh /opt/nvidia-installers/NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run \
	--silent \
	--no-kernel-module --no-kernel-modules \
	--no-nvidia-modprobe --no-drm \
	--no-x-check --no-questions \
	--install-libglvnd --skip-depmod >/tmp/nvidia-install.log 2>&1 || true && \
	ldconfig && \
	mkdir -p /usr/share/glvnd/egl_vendor.d /etc/vulkan/icd.d && \
	printf '%s\n' '{"file_format_version":"1.0.0","ICD":{"library_path":"libEGL_nvidia.so.0"}}' \
	> /usr/share/glvnd/egl_vendor.d/10_nvidia.json && \
	printf '%s\n' '{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.3.0"}}' \
	> /etc/vulkan/icd.d/nvidia_icd.json && \
	rm -f /opt/nvidia-installers/NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run

# 安装 code-server 和 vscode 常用插件
RUN curl -fsSL https://code-server.dev/install.sh | sh

# 然后安装插件（插件下载也可能慢，可考虑离线安装）
RUN code-server --install-extension redhat.vscode-yaml && \
	code-server --install-extension dbaeumer.vscode-eslint && \
	code-server --install-extension eamodio.gitlens && \
	code-server --install-extension tencent-cloud.coding-copilot && \
	code-server --install-extension cnbcool.cnb-welcome && \
	code-server --install-extension ms-azuretools.vscode-docker

#安装node
RUN curl -sL https://deb.nodesource.com/setup_24.x | bash - && \
	apt-get -y install nodejs

RUN npm i -g bun yarn pnpm bun commitizen --registry https://mirrors.cloud.tencent.com/npm/ --allow-scripts=bun && \
	pnpm config set registry https://mirrors.cloud.tencent.com/npm/ && \
	echo "{ \"path\": \"cz-conventional-changelog\" }" > ~/.czrc && \
	bun i -g @anthropic-ai/claude-code
RUN echo "export PATH=$PATH:/root/.bun/bin" >> /root/.bashrc


# 指定字符集支持命令行输入中文（根据需要选择字符集）
ENV LANG=C.UTF-8
ENV LANGUAGE=C.UTF-8

# 安装blender
RUN mkdir -p /usr/local/blender && mkdir -p /usr/local/flamenco

WORKDIR /usr/local/blender
RUN wget --quiet ${BLENDER_TAR_URL} -O blender.tar.xz && \
	tar --no-same-owner -xvf blender.tar.xz -C /usr/local/blender --strip-components=1 && \
	rm blender.tar.xz

WORKDIR /usr/local/flamenco

# 安装flamenco
RUN wget --quiet https://flamenco.blender.org/downloads/flamenco-3.9.2-linux-amd64.tar.gz -O flamenco.tar.gz &&\
	tar --no-same-owner -xzf flamenco.tar.gz -C /usr/local/flamenco --strip-components=1 && \
	chmod +x ./flamenco-manager ./flamenco-worker && \
	rm flamenco.tar.gz
RUN ln -s /usr/local/blender/blender /usr/local/bin/blender && \
	ln -s /usr/local/flamenco/flamenco-manager /usr/local/bin/flamenco-manager && \
	ln -s /usr/local/flamenco/flamenco-worker /usr/local/bin/flamenco-worker

# 暴露VNC端口
# EXPOSE 5900
# EXPOSE 80
# EXPOSE 6000
# ENV DISPLAY=:0


# 清理越界 UID/GID（如 NVIDIA .run 解包残留的高位 UID，例如 1000031），
# 统一归为 0:0，避免在开启 userns-remap 的 GPU 节点上触发
# "failed to register layer: container ID ... cannot be mapped to a host ID"。
RUN find / -xdev \( -uid 100000 -o -gid 100000 \) -exec chown -h 0:0 {} + 2>/dev/null || true

ENTRYPOINT ["/bin/bash"]