#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# render.sh — EEVEE GPU 渲染封装（自动设环境变量 + 修正 -o/-f 顺序）
#
# 用法:
#   bash render.sh <file.blend> [frame] [outdir]
#
# 示例:
#   bash render.sh sandrone.blend 1                # 渲染第1帧 -> /workspace/0001.png
#   bash render.sh sandrone.blend 1 /workspace/out # 输出到指定目录
#   bash render.sh sandrone.blend 1-24 /tmp/seq    # 渲染 1~24 帧序列
# ---------------------------------------------------------------------------
set -euo pipefail

BLEND="${1:?用法: render.sh <file.blend> [frame] [outdir]}"
FRAME="${2:-1}"
OUTDIR="${3:-/workspace}"
mkdir -p "$OUTDIR"

# GPU 图形栈环境（EEVEE 需要）
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg}"; mkdir -p "$XDG_RUNTIME_DIR"
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/nvidia_icd.json}"

OUTPAT="$OUTDIR/####.png"

# 支持单帧(-f)或帧范围(-a with -s/-e)
if [[ "$FRAME" == *-* ]]; then
  S="${FRAME%-*}"; E="${FRAME#*-}"
  echo "[render] EEVEE/Vulkan 序列帧 $S..$E -> $OUTPAT"
  # -o 与 -s/-e 必须在 -a 之前
  blender -b "$BLEND" --gpu-backend vulkan -o "$OUTPAT" -s "$S" -e "$E" -a
else
  echo "[render] EEVEE/Vulkan 单帧 $FRAME -> $OUTPAT"
  # -o 必须在 -f 之前
  blender -b "$BLEND" --gpu-backend vulkan -o "$OUTPAT" -f "$FRAME"
fi
