#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# nvidia-graphics-setup.sh
#
# 让托管容器具备 NVIDIA 用户态图形栈（EGL/GLX/Vulkan/OptiX），使无头 EEVEE
# 渲染走 GPU，而不是回退到 Mesa llvmpipe 在 CPU 上软件渲染。
#
# 背景：基础镜像 cuda:*-runtime 只带 CUDA 计算栈，缺图形用户态库；且用户态库
#       版本必须与宿主机内核模块【精确匹配】。本脚本只装用户态库，绝不碰内核。
#
# 两用：
#   构建时(Dockerfile)  —— 无 GPU，通过环境变量 NVIDIA_DRIVER_VERSION 指定版本预装
#   运行时(start.sh)     —— 有 nvidia-smi，自动读取宿主机真实版本并校正（自愈）
#
# 幂等、最佳努力：任何失败都不会中断（构建/打开环境不被阻塞）。
# ---------------------------------------------------------------------------
set -uo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

log()  { printf '\033[1;32m[nvidia-gfx]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[nvidia-gfx]\033[0m %s\n' "$*" >&2; }

INSTALLER_DIR="${INSTALLER_DIR:-/opt/nvidia-installers}"
EGL_JSON="/usr/share/glvnd/egl_vendor.d/10_nvidia.json"
VK_JSON="/etc/vulkan/icd.d/nvidia_icd.json"   # 与 Dockerfile 的 VK_ICD_FILENAMES 保持一致

write_configs() {
  mkdir -p "$(dirname "$EGL_JSON")" "$(dirname "$VK_JSON")"
  [ -e "$EGL_JSON" ] || printf '%s\n' \
    '{"file_format_version":"1.0.0","ICD":{"library_path":"libEGL_nvidia.so.0"}}' > "$EGL_JSON"
  printf '%s\n' \
    '{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.3.0"}}' > "$VK_JSON"
}

installed_ver() {
  ls /usr/lib/x86_64-linux-gnu/libEGL_nvidia.so.* 2>/dev/null \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# --- 1. 确定目标版本：运行时优先用宿主机真实版本；构建时用环境变量 ------------
TARGET="${NVIDIA_DRIVER_VERSION:-}"
if command -v nvidia-smi >/dev/null 2>&1; then
  V="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ')"
  [ -n "$V" ] && TARGET="$V"
fi
if [ -z "$TARGET" ]; then
  warn "无法确定驱动版本（无 nvidia-smi 且未设 NVIDIA_DRIVER_VERSION），跳过。"
  exit 0
fi

# --- 2. 已匹配则只补配置文件后退出（常见路径，极快） ------------------------
CUR="$(installed_ver)"
if [ -n "$CUR" ] && [ "$CUR" = "$TARGET" ]; then
  write_configs
  log "用户态图形库已匹配 $TARGET，就绪。"
  exit 0
fi
log "目标驱动=$TARGET，当前用户态=${CUR:-无} → 安装/更新用户态库…"

# --- 3. modprobe 依赖（安装器早期硬检查） ----------------------------------
if ! command -v modprobe >/dev/null 2>&1; then
  (apt-get update -qq && apt-get install -y -qq kmod) || warn "安装 kmod 失败，继续尝试。"
fi

# --- 4. 定位或下载与目标版本一致的 .run ------------------------------------
RUN="$INSTALLER_DIR/NVIDIA-Linux-x86_64-${TARGET}.run"
if [ ! -f "$RUN" ]; then
  mkdir -p "$INSTALLER_DIR"
  URL="https://download.nvidia.com/XFree86/Linux-x86_64/${TARGET}/NVIDIA-Linux-x86_64-${TARGET}.run"
  log "下载 $URL"
  if ! wget -q -O "$RUN" "$URL"; then
    warn "下载失败，跳过安装（EEVEE 可能回退 CPU）。稍后可手动重跑本脚本。"
    rm -f "$RUN"
    exit 0
  fi
fi
chmod +x "$RUN"

# --- 5. 只装用户态库（--no-kernel-module，绝不碰宿主机内核模块） ------------
log "静默安装用户态库中…（个别 'Device busy'/systemctl 报错可忽略）"
sh "$RUN" --silent \
  --no-kernel-module --no-kernel-modules \
  --no-nvidia-modprobe --no-drm \
  --no-x-check --no-questions \
  --install-libglvnd --skip-depmod >/tmp/nvidia-install.log 2>&1 || true
ldconfig
write_configs

# --- 6. 校验 ---------------------------------------------------------------
if [ "$(installed_ver)" = "$TARGET" ]; then
  log "✅ 用户态图形库 $TARGET 安装完成，EEVEE 可走 GPU。"
else
  warn "⚠ 安装后版本校验未通过（详见 /tmp/nvidia-install.log），EEVEE 可能仍走 CPU。"
fi
exit 0
