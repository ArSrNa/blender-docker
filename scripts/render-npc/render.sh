#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# render.sh — Blender 渲染入口（供 NPC / CI 调用）
#
# 特性：
#   * 默认引擎 EEVEE（GPU），无 GPU 时自动回退 Cycles（CPU）
#   * 用户/模型用自然语言或 JSON 指定参数，本脚本负责翻译成 Blender 指令
#   * 运行环境缺失时自动自举（装 blender + EGL/Vulkan 用户态库）
#   * 输出目录产物 + 机器可读报告 RENDER_REPORT（JSON）
#
# 用法：
#   bash scripts/render-npc/render.sh --blend test.blend --frame 1
#   bash scripts/render-npc/render.sh --blend a.blend --engine cycles --device cpu \
#        --samples 64 --resolution 1920x1080 --format PNG --frame 1-24
#
# 全部参数：
#   --blend PATH        要渲染的 .blend（必填，或用 RENDER_BLEND 环境变量）
#   --engine NAME       eevee | cycles | workbench | auto   （默认 auto=eevee）
#   --device NAME       gpu | cpu | auto                    （默认 auto）
#   --samples N         采样数
#   --resolution WxH    分辨率，如 1920x1080
#   --res-percent N     分辨率百分比 1-100
#   --frame SPEC        1 | 1,3,5 | 1-24 | 1..24            （默认 1）
#   --format FMT        PNG | JPEG | WEBP | OPEN_EXR | TIFF
#   --outdir DIR        输出目录（默认 /workspace/output）
#   --scene NAME        场景名
#   --camera NAME       摄像机名
#   --threads N         线程数
#   --no-fallback       有 GPU 但渲染失败时不回退 Cycles
#   --auto-install      缺少 blender 时自动下载安装（默认开启，可用 --no-install 关闭）
#   --extra-json JSON   直接透传额外 bpy 指令（高级用法）
# ---------------------------------------------------------------------------
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

BLEND="${RENDER_BLEND:-}"
ENGINE="${RENDER_ENGINE:-auto}"
DEVICE="${RENDER_DEVICE:-auto}"
SAMPLES=""
RESOLUTION=""
RES_PERCENT=""
FRAME="${RENDER_FRAME:-1}"
FORMAT=""
OUTDIR="${RENDER_OUTDIR:-/workspace/output}"
SCENE=""
CAMERA=""
THREADS=""
ALLOW_FALLBACK=1
AUTO_INSTALL=1

log()  { printf '\033[1;36m[render-npc]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[render-npc]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[render-npc]\033[0m %s\n' "$*" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --blend)       BLEND="${2:-}"; shift 2 ;;
    --engine)      ENGINE="${2:-}"; shift 2 ;;
    --device)      DEVICE="${2:-}"; shift 2 ;;
    --samples)     SAMPLES="${2:-}"; shift 2 ;;
    --resolution)  RESOLUTION="${2:-}"; shift 2 ;;
    --res-percent) RES_PERCENT="${2:-}"; shift 2 ;;
    --frame|--frames) FRAME="${2:-}"; shift 2 ;;
    --format)      FORMAT="${2:-}"; shift 2 ;;
    --outdir)      OUTDIR="${2:-}"; shift 2 ;;
    --scene)       SCENE="${2:-}"; shift 2 ;;
    --camera)      CAMERA="${2:-}"; shift 2 ;;
    --threads)     THREADS="${2:-}"; shift 2 ;;
    --no-fallback) ALLOW_FALLBACK=0; shift ;;
    --auto-install) AUTO_INSTALL=1; shift ;;
    --no-install)  AUTO_INSTALL=0; shift ;;
    --extra-json)  EXTRA_JSON="${2:-}"; shift 2 ;;
    -h|--help)     sed -n '2,40p' "$0"; exit 0 ;;
    *) warn "未知参数: $1"; shift ;;
  esac
done

# ---------------------------------------------------------------------------
# 0. 定位 blender（缺了就自举安装）
# ---------------------------------------------------------------------------
find_blender() {
  for c in "${BLENDER_BIN:-}" "$(command -v blender 2>/dev/null)" \
           /usr/local/bin/blender /usr/local/blender/blender /opt/blender/blender; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

install_blender() {
  local major="${BLENDER_MAJOR:-4.5}" ver="${BLENDER_VERSION:-4.5.11}"
  local url="https://mirrors.aliyun.com/blender/release/Blender${major}/blender-${ver}-linux-x64.tar.xz"
  log "未找到 blender，自动安装 $ver …（可用 BLENDER_TAR_URL 覆盖下载源）"
  url="${BLENDER_TAR_URL:-$url}"

  # 运行库依赖（Debian/Ubuntu 通用，已装则秒过）
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y -qq xz-utils curl ca-certificates \
      libsm6 libice6 libxi6 libxrender1 libxkbcommon0 libxext6 libxcursor1 \
      libxinerama1 libxxf86vm1 libglu1-mesa libfreetype6 libgomp1 \
      libegl1 libgl1 libglx0 libglvnd0 >/dev/null 2>&1 || true
  fi

  local tmp; tmp="$(mktemp -d)"
  if ! curl -fsSL --retry 3 -o "$tmp/b.tar.xz" "$url"; then
    err "下载 Blender 失败：$url"; rm -rf "$tmp"; return 1
  fi
  mkdir -p /usr/local/blender
  tar --no-same-owner -xf "$tmp/b.tar.xz" -C /usr/local/blender --strip-components=1 || {
    err "解包失败"; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  ln -sf /usr/local/blender/blender /usr/local/bin/blender 2>/dev/null || true
  command -v blender >/dev/null 2>&1 || BLENDER_BIN=/usr/local/blender/blender
  log "Blender 安装完成: $(("${BLENDER_BIN:-/usr/local/blender/blender}") --version 2>/dev/null | head -1)"
}

BLENDER="$(find_blender || true)"
if [ -z "${BLENDER:-}" ]; then
  if [ "$AUTO_INSTALL" = "1" ]; then
    install_blender || { err "Blender 不可用，无法渲染"; exit 3; }
    BLENDER="$(find_blender || true)"
  fi
fi
[ -z "${BLENDER:-}" ] && { err "找不到 blender 可执行文件（可用 --auto-install 自动安装）"; exit 3; }

# ---------------------------------------------------------------------------
# 1. 校验输入
# ---------------------------------------------------------------------------
[ -z "$BLEND" ] && { err "缺少 --blend <file.blend>"; exit 2; }
case "$BLEND" in /*) ;; *) BLEND="$ROOT/$BLEND" ;; esac
[ -f "$BLEND" ] || { err "找不到 .blend 文件: $BLEND"; exit 2; }
mkdir -p "$OUTDIR"

log "Blender   : $("$BLENDER" --version 2>/dev/null | head -1)"
log "工程文件  : $BLEND"
log "输出目录  : $OUTDIR"

# ---------------------------------------------------------------------------
# 2. 探测 GPU（决定默认引擎）
# ---------------------------------------------------------------------------
GPU_JSON="$(python3 "$HERE/probe_gpu.py" 2>/dev/null || echo '{"gpu":false,"reason":"probe-failed"}')"
HAS_GPU="$(printf '%s' "$GPU_JSON" | python3 -c 'import sys,json;print("1" if json.load(sys.stdin).get("gpu") else "0")' 2>/dev/null || echo 0)"
log "GPU 探测  : $GPU_JSON"

if [ "$HAS_GPU" = "1" ]; then
  # 尝试对齐 NVIDIA 用户态图形栈（幂等、失败不阻塞）
  if [ -x "$ROOT/.ide/nvidia-graphics-setup.sh" ] && [ "${RENDER_SKIP_GFX_SETUP:-0}" != "1" ]; then
    bash "$ROOT/.ide/nvidia-graphics-setup.sh" >/tmp/gfx-setup.log 2>&1 || true
  fi
fi

if [ "$ENGINE" = "auto" ] || [ -z "$ENGINE" ]; then
  if [ "$HAS_GPU" = "1" ]; then
    ENGINE="eevee"; DEVICE="${DEVICE:-gpu}"
    log "引擎选择  : EEVEE（检测到 GPU）"
  else
    ENGINE="cycles"; DEVICE="cpu"
    log "引擎选择  : CYCLES/CPU（无 GPU，默认 EEVEE 已自动回退）"
  fi
fi

# ---------------------------------------------------------------------------
# 3. 组装 bpy 指令 payload
# ---------------------------------------------------------------------------
PAYLOAD="$(mktemp)"
export RENDER_ENGINE="$ENGINE" RENDER_DEVICE="$DEVICE" RENDER_SAMPLES="$SAMPLES" \
       RENDER_RESOLUTION="$RESOLUTION" RENDER_RES_PERCENT="$RES_PERCENT" \
       RENDER_FRAME="$FRAME" RENDER_FORMAT="$FORMAT" RENDER_OUTDIR="$OUTDIR" \
       RENDER_SCENE="$SCENE" RENDER_CAMERA="$CAMERA" RENDER_THREADS="$THREADS" \
       RENDER_EXTRA="${EXTRA_JSON:-}"
python3 - "$PAYLOAD" <<'PY'
import json, os, sys
def g(k):
    v = os.environ.get(k, "")
    return v if v != "" else None
def gi(k):
    v = g(k)
    try: return int(v)
    except (TypeError, ValueError): return None
p = {
    "engine": g("RENDER_ENGINE"), "device": g("RENDER_DEVICE"),
    "samples": gi("RENDER_SAMPLES"), "resolution": g("RENDER_RESOLUTION"),
    "res_percent": gi("RENDER_RES_PERCENT"), "frame": g("RENDER_FRAME"),
    "format": g("RENDER_FORMAT"), "outdir": g("RENDER_OUTDIR"),
    "scene": g("RENDER_SCENE"), "camera": g("RENDER_CAMERA"),
    "threads": gi("RENDER_THREADS"),
}
extra = g("RENDER_EXTRA")
if extra:
    try: p.update(json.loads(extra))
    except Exception as e: print("[render-npc] --extra-json 解析失败:", e, file=sys.stderr)
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(p, ensure_ascii=False))
PY
log "指令      : $(cat "$PAYLOAD")"

# ---------------------------------------------------------------------------
# 4. 执行渲染（GPU 后端优先，失败自动回退 CPU）
# ---------------------------------------------------------------------------
run_blender() {
  local backend="$1" logf="$2"
  local gpuargs=()
  [ -n "$backend" ] && gpuargs=(--gpu-backend "$backend")
  "$BLENDER" -b "$BLEND" "${gpuargs[@]}" --factory-startup \
      --python-exit-code 1 \
      -P "$HERE/blender_render.py" -- --payload "$PAYLOAD" 2>&1 | tee "$logf"
  return "${PIPESTATUS[0]}"
}

GPU_BACKEND=""
[ "$ENGINE" = "eevee" ] && GPU_BACKEND="vulkan"

LOG="$OUTDIR/render.log"
log "开始渲染  : engine=$ENGINE device=$DEVICE frame=$FRAME"
set +e
run_blender "$GPU_BACKEND" "$LOG"
RC=$?
set -e 2>/dev/null || true

REPORT_LINE="$(grep -h '^RENDER_REPORT=' "$LOG" 2>/dev/null | tail -1 | sed 's/^RENDER_REPORT=//')"

# GPU 路径失败 → 回退 Cycles CPU（用户没显式指定 engine 时）
if [ "$RC" -ne 0 ] && [ "$ENGINE" = "eevee" ] && [ "$ALLOW_FALLBACK" = "1" ] && \
   [ "${RENDER_ENGINE:-auto}" = "auto" ]; then
  warn "EEVEE/GPU 渲染失败（exit=$RC），回退 CYCLES/CPU 重试…"
  python3 - "$PAYLOAD" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
p.update({"engine": "cycles", "device": "cpu", "fallback": True})
# 回退时不锁定采样数，避免用户给 EEVEE 的采样值拖慢 CPU 渲染
p.pop("samples", None)
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
  LOG="$OUTDIR/render-fallback.log"
  run_blender "" "$LOG"
  RC=$?
  REPORT_LINE="$(grep -h '^RENDER_REPORT=' "$LOG" 2>/dev/null | tail -1 | sed 's/^RENDER_REPORT=//')"
fi

# ---------------------------------------------------------------------------
# 5. 汇总报告
# ---------------------------------------------------------------------------
echo
echo "======================= RENDER SUMMARY ======================="
if [ "$RC" -eq 0 ]; then
  printf '\033[1;32m✅ 渲染成功\033[0m\n'
else
  printf '\033[1;31m❌ 渲染失败 (exit=%s)\033[0m\n' "$RC"
  tail -30 "$LOG" 2>/dev/null
fi
ls -lh "$OUTDIR" 2>/dev/null | grep -vE '\.log$' || true
[ -n "${REPORT_LINE:-}" ] && printf '%s\n' "$REPORT_LINE"
echo "=============================================================="
cp -f "$PAYLOAD" "$OUTDIR/render-request.json" 2>/dev/null || true
rm -f "$PAYLOAD"
exit "$RC"
