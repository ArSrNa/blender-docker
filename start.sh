#!/bin/bash
# 从仓库所在目录运行，保证能找到 .ide/ 下的脚本（不依赖镜像内文件）。
cd "$(dirname "$0")" || exit 1
# 校正 NVIDIA 用户态图形栈以匹配宿主机真实驱动版本（EEVEE 走 GPU 的关键；自愈）。
# 与 .cnb.yml 的 "setup GPU" 阶段调用同一脚本；脚本幂等，重复运行会秒退。
mkdir -p "${XDG_RUNTIME_DIR:-/tmp/xdg}"
if [ -f .ide/nvidia-graphics-setup.sh ]; then
	bash .ide/nvidia-graphics-setup.sh || true
fi

cp config/flamenco-manager.yaml /usr/local/flamenco/flamenco-manager.yaml
cd /usr/local/flamenco/
./flamenco-worker &
./flamenco-manager &