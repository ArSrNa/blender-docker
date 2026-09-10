#!/usr/bin/env python3
"""
blender_render.py — Blender 渲染参数解释器（在 blender 的 Python 环境里运行）

职责：把 NPC 解析出来的「渲染指令」翻译成 bpy / scene 设置，并执行渲染。
参数通过环境变量或 --payload <json> 传入。

支持的指令字段（全部可选，未给的沿用 .blend 内已有设置）：
  engine        渲染引擎: eevee | cycles | workbench | auto(默认)
  device        设备: gpu | cpu | auto(默认)         仅对 cycles 有意义
  samples       采样数（eevee=taa_render_samples / cycles=samples）
  resolution    分辨率，如 "1920x1080"
  res_percent   分辨率百分比 1-100
  frame         帧，支持 "1"、"1,3,5"、"1-10"、"1..10"
  format        图片格式: PNG|JPEG|WEBP|OPEN_EXR|TIFF|BMP|TARGA
  outdir        输出目录
  scene         场景名
  camera        摄像机名
  transparent   是否透明背景
  film          保持 .blend 的电影设置
  threads       线程数
  verbose       打印更多信息

用法（由 bash 包装脚本调用）：
  blender -b file.blend -P blender_render.py -- --payload /tmp/payload.json
"""

import json
import os
import sys

import bpy

SEP = "=" * 62


def log(*a):
    print("[render]", *a, flush=True)


# --------------------------------------------------------------------------
# 参数读取
# --------------------------------------------------------------------------
def read_payload():
    argv = sys.argv
    payload_file = None
    if "--payload" in argv:
        payload_file = argv[argv.index("--payload") + 1]
    raw = os.environ.get("RENDER_PAYLOAD", "")
    if payload_file and os.path.exists(payload_file):
        raw = open(payload_file, encoding="utf-8").read()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except Exception as e:  # noqa: BLE001
        log("payload 解析失败，忽略:", e)
        return {}


# --------------------------------------------------------------------------
# 设备能力探测（只读，不改渲染结果）
# --------------------------------------------------------------------------
def detect_gpu():
    """返回 (has_gpu, devices, note)。has_gpu=True 表示存在非 CPU 的 Cycles 设备。"""
    addon = bpy.context.preferences.addons.get("cycles")
    if not addon:
        return False, [], "cycles addon 不可用"
    prefs = addon.preferences
    found = []
    keep = prefs.compute_device_type
    try:
        for t in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
            try:
                prefs.compute_device_type = t
                prefs.refresh_devices()
                for d in prefs.devices:
                    if d.type != "CPU":
                        found.append((t, d.name, d.type))
            except Exception:  # noqa: BLE001
                continue
    finally:
        try:
            prefs.compute_device_type = keep
        except Exception:  # noqa: BLE001
            pass
    return bool(found), found, ""


def gpu_stack_hint():
    """非 bpy 侧的环境判断：有 /dev/nvidia* 但没有 EGL/Vulkan nvidia 配置 → 图形栈缺失。"""
    import glob
    has_dev = bool(glob.glob("/dev/nvidia[0-9]*")) or os.path.exists("/dev/nvidiactl")
    has_egl = bool(glob.glob("/usr/share/glvnd/egl_vendor.d/*nvidia*"))
    has_vk = bool(glob.glob("/usr/share/vulkan/icd.d/*nvidia*")) or \
        bool(glob.glob("/etc/vulkan/icd.d/*nvidia*"))
    return has_dev, has_egl or has_vk


# --------------------------------------------------------------------------
# 参数翻译
# --------------------------------------------------------------------------
ENGINE_MAP = {
    "eevee": "BLENDER_EEVEE_NEXT",
    "eevee-next": "BLENDER_EEVEE_NEXT",
    "eevee_legacy": "BLENDER_EEVEE",
    "cycles": "CYCLES",
    "workbench": "BLENDER_WORKBENCH",
}

FORMAT_MAP = {
    "png": "PNG", "jpg": "JPEG", "jpeg": "JPEG", "webp": "WEBP",
    "exr": "OPEN_EXR", "open_exr": "OPEN_EXR", "tiff": "TIFF", "tif": "TIFF",
    "bmp": "BMP", "targa": "TARGA", "tga": "TARGA",
}


def parse_frames(spec):
    """把帧描述转成 (start, end, is_anim, frame_list)。"""
    if spec is None:
        return None
    spec = str(spec).strip()
    frames = []
    for chunk in spec.replace("..", "-").split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "-" in chunk[1:]:
            a, b = chunk.split("-", 1)
            try:
                frames.extend(range(int(a), int(b) + 1))
                continue
            except ValueError:
                pass
        try:
            frames.append(int(chunk))
        except ValueError:
            continue
    if not frames:
        return None
    frames = sorted(set(frames))
    return frames


def apply_resolution(scene, spec):
    s = str(spec).strip().lower().replace(" ", "")
    for sep in ("x", "*", "×"):
        if sep in s:
            a, b = s.split(sep, 1)
            try:
                scene.render.resolution_x = int(a)
                scene.render.resolution_y = int(b)
                return True
            except ValueError:
                return False
    return False


def pick_scene(payload):
    name = payload.get("scene")
    if name:
        for s in bpy.data.scenes:
            if s.name == name:
                return s
        log(f"⚠ 未找到场景 {name}，使用当前活动场景 {bpy.context.scene.name}")
    return bpy.context.scene


def apply_camera(scene, payload):
    name = payload.get("camera")
    if not name:
        return
    cam = bpy.data.objects.get(name)
    if cam and cam.type == "CAMERA":
        scene.camera = cam
        log("摄像机 →", name)
    else:
        log(f"⚠ 未找到摄像机 {name}，保持原设置")


def set_engine(scene, engine):
    ident = ENGINE_MAP.get(engine, "BLENDER_EEVEE_NEXT")
    scene.render.engine = ident
    return ident


def set_device(scene, device, device_type=None):
    """设置 Cycles 渲染设备。返回实际使用的 device 字符串。"""
    if not hasattr(scene, "cycles"):
        return device
    addon = bpy.context.preferences.addons.get("cycles")
    if device == "gpu" and addon:
        prefs = addon.preferences
        for t in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
            try:
                prefs.compute_device_type = t
                prefs.refresh_devices()
                gpus = [d for d in prefs.devices if d.type != "CPU"]
                if gpus:
                    for d in prefs.devices:
                        d.use = d.type != "CPU"
                    scene.cycles.device = "GPU"
                    log(f"Cycles 设备 → GPU ({t}: {', '.join(d.name for d in gpus)})")
                    return "gpu"
            except Exception:  # noqa: BLE001
                continue
        log("⚠ 请求 GPU 但未发现可用 GPU 设备，回退 CPU")
    scene.cycles.device = "CPU"
    if addon:
        try:
            addon.preferences.compute_device_type = "NONE"
        except Exception:  # noqa: BLE001
            pass
    return "cpu"


def apply(payload):
    scene = pick_scene(payload)
    bpy.context.window.scene = scene

    report = {
        "blender": bpy.app.version_string,
        "scene": scene.name,
        "engine_requested": payload.get("engine", "auto"),
        "engine_used": "",
        "device_requested": payload.get("device", "auto"),
        "device_used": "",
        "notes": [],
    }

    # ---- 引擎 / 设备 ----
    req_engine = str(payload.get("engine", "auto")).lower()
    req_device = str(payload.get("device", "auto")).lower()

    orig_engine = scene.render.engine
    if req_engine in ("auto", "", "none"):
        req_engine = "eevee" if orig_engine != "CYCLES" else "cycles"

    has_gpu, gpus, note = detect_gpu()
    if note:
        report["notes"].append(note)

    if req_engine == "cycles":
        engine_used = set_engine(scene, "cycles")
        if req_device == "gpu":
            used = set_device(scene, "gpu")
        elif req_device == "cpu":
            used = set_device(scene, "cpu")
        else:  # auto
            used = set_device(scene, "gpu" if has_gpu else "cpu")
        report["device_used"] = used
        if has_gpu:
            report["notes"].append(f"GPU 设备: {[g[1] for g in gpus]}")
    else:
        # EEVEE / Workbench 走 GPU 后端，无 GPU 时 Blender 自动回落 llvmpipe
        engine_used = set_engine(scene, req_engine)
        if has_gpu:
            report["device_used"] = "gpu"
        else:
            has_dev, has_stack = gpu_stack_hint()
            if has_dev and not has_stack:
                report["device_used"] = "cpu(llvmpipe · 缺 NVIDIA 图形栈)"
                report["notes"].append(
                    "检测到 GPU 设备但缺少 EGL/Vulkan 用户态库，EEVEE 回落软件渲染。"
                    "可运行 bash gpu-setup/setup_gpu.sh 修复。")
            else:
                report["device_used"] = "cpu(llvmpipe)"
                report["notes"].append("无可用 GPU，EEVEE 使用 CPU 软件渲染(llvmpipe)。")

    report["engine_used"] = engine_used

    # ---- 采样 ----
    if payload.get("samples") is not None:
        n = int(payload["samples"])
        if engine_used == "CYCLES":
            scene.cycles.samples = n
        elif hasattr(scene, "eevee"):
            scene.eevee.taa_render_samples = n
        log("采样数 →", n)

    # ---- 分辨率 / 格式 ----
    if payload.get("resolution"):
        if apply_resolution(scene, payload["resolution"]):
            log("分辨率 →", scene.render.resolution_x, "x", scene.render.resolution_y)
        else:
            log("⚠ 分辨率格式错误:", payload["resolution"])
    if payload.get("res_percent") is not None:
        scene.render.resolution_percentage = max(1, min(100, int(payload["res_percent"])))

    if payload.get("format"):
        fmt = FORMAT_MAP.get(str(payload["format"]).lower())
        if fmt:
            scene.render.image_settings.file_format = fmt
            log("输出格式 →", fmt)
        else:
            log("⚠ 未知格式:", payload["format"])

    if payload.get("transparent") is not None:
        scene.render.film_transparent = bool(payload["transparent"])

    if payload.get("threads") is not None:
        scene.render.threads_mode = "FIXED"
        scene.render.threads = int(payload["threads"])

    apply_camera(scene, payload)

    # ---- 输出路径 ----
    outdir = payload.get("outdir") or "/workspace/output"
    os.makedirs(outdir, exist_ok=True)
    frames = parse_frames(payload.get("frame"))
    scene.render.filepath = os.path.join(outdir, "frame_")

    report.update({
        "resolution": f"{scene.render.resolution_x}x{scene.render.resolution_y}"
                      f"@{scene.render.resolution_percentage}%",
        "format": scene.render.image_settings.file_format,
        "outdir": outdir,
        "frames": frames,
        "camera": scene.camera.name if scene.camera else None,
    })
    return scene, frames, report


def render(scene, frames):
    if frames and len(frames) == 1:
        scene.frame_set(frames[0])
        log(f"单帧渲染 frame={frames[0]}")
        bpy.ops.render.render(write_still=True)
        return [frames[0]]
    if frames:
        scene.frame_start = frames[0]
        scene.frame_end = frames[-1]
        log(f"序列渲染 frames={frames[0]}..{frames[-1]} (共 {len(frames)} 帧)")
    else:
        log(f"动画渲染 frames={scene.frame_start}..{scene.frame_end}")
    bpy.ops.render.render(animation=True)
    return frames or list(range(scene.frame_start, scene.frame_end + 1))


def main():
    payload = read_payload()
    log(SEP)
    if payload:
        log("指令:", json.dumps({k: v for k, v in payload.items() if v is not None},
                                ensure_ascii=False))
    try:
        scene, frames, report = apply(payload)
    except Exception as e:  # noqa: BLE001
        log("❌ 应用参数失败:", e)
        print("RENDER_REPORT=" + json.dumps({"ok": False, "error": str(e)},
                                            ensure_ascii=False))
        sys.exit(1)

    log(f"引擎: {report['engine_requested']} → {report['engine_used']} | "
        f"设备: {report['device_requested']} → {report['device_used']}")
    for n in report["notes"]:
        log("提示:", n)

    try:
        rendered = render(scene, frames)
    except Exception as e:  # noqa: BLE001
        log("❌ 渲染失败:", e)
        print("RENDER_REPORT=" + json.dumps({"ok": False, "error": str(e),
                                             **report}, ensure_ascii=False))
        sys.exit(1)

    outdir = report["outdir"]
    files = sorted(
        os.path.join(outdir, f) for f in os.listdir(outdir)
        if os.path.isfile(os.path.join(outdir, f))
    )
    report.update({"ok": True, "rendered": rendered, "files": files})
    log("✅ 渲染完成，输出:", outdir)
    print(SEP)
    print("RENDER_REPORT=" + json.dumps(report, ensure_ascii=False))
    print(SEP)


if __name__ == "__main__":
    main()
