FROM nvidia/cudagl:11.4.2-base-ubuntu20.04
# 修改镜像源
RUN sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list && \
	sed -i 's/security.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list && \
	sed -i 's/cn.archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list

# 设置时区
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
	echo "Asia/Shanghai" > /etc/timezone

ENV BLENDER_MAJOR 3.6
ENV BLENDER_VERSION 3.6.14
ENV BLENDER_TAR_URL https://mirrors.aliyun.com/blender/release/Blender${BLENDER_MAJOR}/blender-${BLENDER_VERSION}-linux-x64.tar.xz

RUN apt-get update && \
	apt-get install -y \
	curl wget nano \
	bzip2 libfreetype6 libgl1-mesa-dev \
	libglu1-mesa \
	libxi6 libxrender1 libxkbcommon0 \
	libsm6 libxext6 libxcursor1 libxinerama1 libgl1-mesa-glx \
	xz-utils && \
	apt-get -y autoremove

# Install blender
RUN mkdir /usr/local/blender && \
	wget --quiet ${BLENDER_TAR_URL} -O blender.tar.xz && \
	tar -xvf blender.tar.xz -C /usr/local/blender --strip-components=1 && \
	rm blender.tar.xz

VOLUME /media

COPY ./entry.sh /start.sh
RUN chmod +x /start.sh
ENTRYPOINT ["/start.sh"]