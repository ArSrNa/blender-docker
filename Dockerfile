FROM nvidia/cudagl:11.4.2-base-ubuntu20.04
# FROM cnbcool/default-dev-env:latest
# 修改镜像源
RUN sed -i 's/archive.ubuntu.com/mirrors.tencent.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.tencent.com/g' /etc/apt/sources.list && \
    sed -i 's/cn.archive.ubuntu.com/mirrors.tencent.com/g' /etc/apt/sources.list

# 设置时区
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

ARG BLENDER_MAJOR
ARG BLENDER_VERSION

ENV BLENDER_TAR_URL https://mirrors.aliyun.com/blender/release/Blender${BLENDER_MAJOR}/blender-${BLENDER_VERSION}-linux-x64.tar.xz

RUN apt-get update && \
    apt-get install -y \
    curl wget nano git git-lfs unzip openssh-server \
    bzip2 libfreetype6 libgl1-mesa-dev \
    libglu1-mesa \
    libxi6 libxrender1 libxkbcommon0 \
    libsm6 libxext6 libxcursor1 libxinerama1 libgl1-mesa-glx \
    xz-utils htop axel && \
    apt-get -y autoremove 

# 指定字符集支持命令行输入中文（根据需要选择字符集）
ENV LANG C.UTF-8
ENV LANGUAGE C.UTF-8

# Install blender
RUN mkdir -p /usr/local/blender
RUN wget --quiet ${BLENDER_TAR_URL} -O blender.tar.xz && \
    tar -xvf blender.tar.xz -C /usr/local/blender --strip-components=1 && \
    rm blender.tar.xz
RUN ln -s /usr/local/blender/blender /usr/local/bin/blender

ENTRYPOINT ["/bin/bash"]