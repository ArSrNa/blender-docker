"""
probe_gpu.py — 探测当前机器是否具备可用于 EEVEE 的 GPU（NVIDIA 硬件 EGL / Vulkan）。

输出：单行 JSON，例如
  {"gpu": true, "reason": "ecgl-nvidia", "driver": "580.95.05", "detail": "NVIDIA GeForce RTX 4090"}

判定顺序（任一条命中即为有 GPU）：
  1. /dev/nvidia* 设备节点存在 + egl_vendor.d 里注册了 NVIDIA EGL 库
  2. glvnd EGL 能枚举出 vendor 含 NVIDIA 的设备
  3. Vulkan ICD 里存在 NVIDIA ICD

用法：python3 probe_gpu.py
"""

import ctypes as C
import glob
import json
import os
import subprocess
import sys


def _sh(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=20)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def driver_version():
    v = _sh("nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null")
    if v:
        return v.splitlines()[0].strip()
    try:
        with open("/proc/driver/nvidia/version", "r", encoding="utf-8") as f:
            line = f.readline()
        # NVIDIA UNIX x86_64 Kernel Module  580.95.05  ...
        parts = line.split()
        for p in parts:
            if p[:3].isdigit() and p.count(".") == 2:
                return p
    except Exception:
        pass
    return ""


def egl_has_nvidia():
    """用 glvnd 扩展枚举 EGL 设备，看有没有 NVIDIA。"""
    try:
        egl = C.CDLL("libEGL.so.1")
    except OSError:
        return False, ""
    try:
        egl.eglGetProcAddress.restype = C.c_void_p
        qd = egl.eglGetProcAddress(b"eglQueryDevicesEXT")
        gp = egl.eglGetProcAddress(b"eglGetPlatformDisplayEXT")
        if not qd or not gp:
            return False, ""
        D = C.c_void_p
        devs = (D * 16)()
        n = C.c_int(0)
        C.CFUNCTYPE(C.c_uint, C.c_int, C.POINTER(D), C.POINTER(C.c_int))(qd)(16, devs, C.byref(n))
        GPD = C.CFUNCTYPE(C.c_void_p, C.c_uint, C.c_void_p, C.POINTER(C.c_int))(gp)
        egl.eglInitialize.restype = C.c_uint
        egl.eglQueryString.restype = C.c_char_p
        for i in range(n.value):
            dpy = GPD(0x313F, devs[i], None)  # EGL_PLATFORM_DEVICE_EXT
            mj, mn = C.c_int(0), C.c_int(0)
            if egl.eglInitialize(C.c_void_p(dpy), C.byref(mj), C.byref(mn)):
                v = egl.eglQueryString(C.c_void_p(dpy), 0x3053)  # EGL_VENDOR
                if v and b"NVIDIA" in v:
                    return True, v.decode(errors="ignore")
    except Exception:
        pass
    return False, ""


def vulkan_has_nvidia():
    for pat in ("/usr/share/vulkan/icd.d/*nvidia*", "/etc/vulkan/icd.d/*nvidia*"):
        if glob.glob(pat):
            return True
    out = _sh("vulkaninfo --summary 2>/dev/null | grep -i nvidia | head -1")
    return bool(out)


def main():
    ver = driver_version()
    nv_dev = bool(glob.glob("/dev/nvidia[0-9]*")) or os.path.exists("/dev/nvidiactl")
    egl_cfg = bool(glob.glob("/usr/share/glvnd/egl_vendor.d/*nvidia*"))
    detail = _sh("nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null").splitlines()
    detail = detail[0].strip() if detail else ""

    if nv_dev and (egl_cfg or ver):
        ok, vendor = egl_has_nvidia()
        if ok or egl_cfg:
            out = {"gpu": True, "reason": "nvidia-egl", "driver": ver, "detail": detail or vendor}
            print(json.dumps(out, ensure_ascii=False))
            return

    ok, vendor = egl_has_nvidia()
    if ok:
        print(json.dumps({"gpu": True, "reason": "egl-nvidia", "driver": ver,
                          "detail": detail or vendor}, ensure_ascii=False))
        return

    if vulkan_has_nvidia():
        print(json.dumps({"gpu": True, "reason": "vulkan-nvidia", "driver": ver,
                          "detail": detail}, ensure_ascii=False))
        return

    print(json.dumps({"gpu": False, "reason": "no-nvidia-graphics-stack",
                      "driver": ver, "detail": detail}, ensure_ascii=False))


if __name__ == "__main__":
    sys.exit(main())
