#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup_gpu.sh — 在托管容器里补装 NVIDIA 用户态图形栈，让 EEVEE 走 GPU
#
# 背景：容器以 NVIDIA_DRIVER_CAPABILITIES=compute,utility 启动，只有 CUDA 计算栈，
#       缺 EGL/OpenGL/Vulkan 用户态库，导致 EEVEE 回退到 CPU 软件渲染(llvmpipe)。
#       本脚本用与宿主机内核模块【完全同版本】的官方 .run，只装用户态库(不碰内核)。
#
# 用法：  sudo bash setup_gpu.sh          # 容器重启后跑一次即可
# 幂等：  已装好则直接跳过，可反复运行
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$PATH:/usr/sbin:/sbin"

log() { printf '\033[1;32m[gpu-setup]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[gpu-setup] ERROR:\033[0m %s\n' "$*" >&2; }

# --- 0. 必须 root ----------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then err "需要 root 运行 (sudo bash setup_gpu.sh)"; exit 1; fi

# --- 1. 探测宿主机驱动版本 -------------------------------------------------
if [ ! -e /proc/driver/nvidia/version ]; then
  err "/proc/driver/nvidia/version 不存在——容器没挂到 NVIDIA 内核模块，无法继续。"
  exit 1
fi
VER="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ')"
[ -z "$VER" ] && { err "读不到驱动版本"; exit 1; }
log "宿主机驱动版本: $VER"

# --- 2. 是否已装好？(幂等检查) --------------------------------------------
if [ -e /usr/share/glvnd/egl_vendor.d/10_nvidia.json ] && \
   ls /usr/lib/x86_64-linux-gnu/libEGL_nvidia.so.* >/dev/null 2>&1; then
  INSTALLED="$(basename "$(ls /usr/lib/x86_64-linux-gnu/libEGL_nvidia.so.* 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)")" || true
  if [ "$INSTALLED" = "$VER" ]; then
    log "用户态库已是 $VER，跳过安装。直接进入自检。"
    SKIP_INSTALL=1
  else
    log "已装版本($INSTALLED) 与驱动($VER) 不符，重装。"
  fi
fi

if [ -z "${SKIP_INSTALL:-}" ]; then
  # --- 3. modprobe 依赖 (安装器早期硬检查) --------------------------------
  if ! command -v modprobe >/dev/null 2>&1; then
    log "安装 kmod (提供 modprobe)…"
    apt-get update -qq && apt-get install -y -qq kmod
  fi

  # --- 4. 定位或下载 .run --------------------------------------------------
  RUN="$HERE/NVIDIA-${VER}.run"
  if [ ! -f "$RUN" ]; then
    log "本地无 $RUN，从 NVIDIA 下载…"
    URL="https://download.nvidia.com/XFree86/Linux-x86_64/${VER}/NVIDIA-Linux-x86_64-${VER}.run"
    wget -q --show-progress -O "$RUN" "$URL" || { err "下载失败: $URL"; rm -f "$RUN"; exit 1; }
  fi
  chmod +x "$RUN"
  log "使用安装器: $RUN"

  # --- 5. 只装用户态库(绝不碰内核模块) ------------------------------------
  log "静默安装用户态库中… (个别 'Device busy'/systemctl 报错可忽略)"
  sh "$RUN" \
    --silent \
    --no-kernel-module --no-kernel-modules \
    --no-nvidia-modprobe --no-drm \
    --no-x-check --no-questions \
    --install-libglvnd --skip-depmod || true   # 忙碌的计算库覆盖失败属正常，不中断
  ldconfig
fi

# --- 6. 修复 EGL vendor 配置 ----------------------------------------------
mkdir -p /usr/share/glvnd/egl_vendor.d
if [ ! -e /usr/share/glvnd/egl_vendor.d/10_nvidia.json ]; then
  cat > /usr/share/glvnd/egl_vendor.d/10_nvidia.json <<'JSON'
{"file_format_version":"1.0.0","ICD":{"library_path":"libEGL_nvidia.so.0"}}
JSON
  log "写入 10_nvidia.json"
fi

# --- 7. 修复 Vulkan ICD ----------------------------------------------------
mkdir -p /usr/share/vulkan/icd.d
if ! ls /usr/share/vulkan/icd.d/ 2>/dev/null | grep -qi nvidia; then
  cat > /usr/share/vulkan/icd.d/nvidia_icd.json <<'JSON'
{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.3.0"}}
JSON
  log "写入 nvidia_icd.json"
fi

# --- 8. 自检：NVIDIA 硬件 EGL 能否初始化 -----------------------------------
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg}"; mkdir -p "$XDG_RUNTIME_DIR"
log "自检 NVIDIA 硬件 EGL 上下文…"
python3 - <<'PY'
import ctypes as C, sys
try:
    egl = C.CDLL("libEGL.so.1")
    egl.eglGetProcAddress.restype = C.c_void_p
    qd = egl.eglGetProcAddress(b"eglQueryDevicesEXT")
    gp = egl.eglGetProcAddress(b"eglGetPlatformDisplayEXT")
    D = C.c_void_p; devs=(D*16)(); n=C.c_int(0)
    C.CFUNCTYPE(C.c_uint, C.c_int, C.POINTER(D), C.POINTER(C.c_int))(qd)(16, devs, C.byref(n))
    GPD = C.CFUNCTYPE(C.c_void_p, C.c_uint, C.c_void_p, C.POINTER(C.c_int))(gp)
    egl.eglInitialize.restype=C.c_uint; egl.eglQueryString.restype=C.c_char_p
    ok_nv=False
    for i in range(n.value):
        dpy=GPD(0x313F, devs[i], None); mj=C.c_int(0); mn=C.c_int(0)
        if egl.eglInitialize(C.c_void_p(dpy), C.byref(mj), C.byref(mn)):
            v=egl.eglQueryString(C.c_void_p(dpy),0x3053)
            print(f"  device[{i}] EGL {mj.value}.{mn.value} vendor={v.decode()}")
            if v and b"NVIDIA" in v: ok_nv=True
    sys.exit(0 if ok_nv else 3)
except Exception as e:
    print("  自检异常:", e); sys.exit(3)
PY
if [ $? -eq 0 ]; then
  log "✅ NVIDIA 硬件 EGL 可用。EEVEE 现在能走 GPU。"
  echo
  echo "  渲染示例（注意 -o 必须在 -f 之前）："
  echo "    export XDG_RUNTIME_DIR=/tmp/xdg && mkdir -p \$XDG_RUNTIME_DIR"
  echo "    export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json"
  echo "    blender -b your.blend --gpu-backend vulkan -o /workspace/####.png -f 1"
  echo
  echo "  或直接用配套脚本：  bash $HERE/render.sh your.blend 1"
else
  err "❌ NVIDIA 硬件 EGL 仍不可用。可能容器完全没图形能力，"
  err "   请找平台把 NVIDIA_DRIVER_CAPABILITIES 改为包含 graphics（或 all）。"
  exit 1
fi
