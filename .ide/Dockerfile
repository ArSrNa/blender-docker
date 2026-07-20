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
ENV BLENDER_TAR_URL https://mirrors.aliyun.com/blender/release/Blender${BLENDER_MAJOR}/blender-${BLENDER_VERSION}-linux-x64.tar.xz

# 4.5以上需要Vulkan
RUN apt-get update && \
	apt-get install -y \
	curl wget nano git git-lfs unzip openssh-server \
	bzip2 libfreetype6 \
	libglu1-mesa \
	libxi6 libxrender1 libxkbcommon0 \
	libsm6 libxext6 libxcursor1 libxinerama1 libgl1-mesa-dev libgl1-mesa-glx libgl1-mesa-dri libegl1 \
	xz-utils htop axel vulkan-tools libvulkan1 libvulkan-dev mesa-vulkan-drivers mesa-utils-extra

#VNC环境
# RUN apt install x11vnc xvfb dbus-x11 kde-standard novnc dbus-x11 && \
# 	apt-get -y autoremove 
# ENV VNC_PASSWORD cnb666

# Vulkan 相关环境变量
ENV VK_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json
ENV VK_LAYER_PATH=/usr/share/vulkan/explicit_layer.d
ENV VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation

# 安装 code-server 和 vscode 常用插件
RUN curl -fsSL https://code-server.dev/install.sh | sh \
	&& code-server --install-extension redhat.vscode-yaml \
	&& code-server --install-extension dbaeumer.vscode-eslint \
	&& code-server --install-extension eamodio.gitlens \
	&& code-server --install-extension tencent-cloud.coding-copilot \
	&& code-server --install-extension cnbcool.cnb-welcome \
	&& code-server --install-extension ms-azuretools.vscode-docker

# 指定字符集支持命令行输入中文（根据需要选择字符集）
ENV LANG C.UTF-8
ENV LANGUAGE C.UTF-8

# 安装blender
RUN mkdir -p /usr/local/blender && mkdir -p /usr/local/flamenco

WORKDIR /usr/local/blender
RUN wget --quiet ${BLENDER_TAR_URL} -O blender.tar.xz && \
	tar -xvf blender.tar.xz -C /usr/local/blender --strip-components=1 && \
	rm blender.tar.xz

WORKDIR /usr/local/flamenco

# 安装flamenco
RUN wget --quiet https://flamenco.blender.org/downloads/flamenco-3.9.2-linux-amd64.tar.gz -O flamenco.tar.gz &&\
	tar -xzf flamenco.tar.gz -C /usr/local/flamenco --strip-components=1 && \
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


ENTRYPOINT ["/bin/bash"]