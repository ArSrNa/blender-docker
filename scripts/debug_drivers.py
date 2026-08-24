"""
Blender Driver 除零错误 & CLI 渲染相机异常 排查脚本

用法:
  blender -b your_file.blend --python debug_drivers.py

或在中 GUI Scripting 面板直接运行。
"""

import bpy
import math

SEP = "=" * 60
SUB = "-" * 40

print(SEP)
print("Blender Driver & Camera Debug Script")
print(SEP)

# ──────────────────────────────────────────────
# [1] 搜索所有包含 tan / angle 的 Driver
# ──────────────────────────────────────────────
print(f"\n[1] 搜索包含 tan/angle 的 Driver")
print(SUB)

def scan_drivers(id_block, label):
    """扫描某个 ID 块上的所有 driver"""
    ad = getattr(id_block, 'animation_data', None)
    if not ad or not ad.drivers:
        return
    for fc in ad.drivers:
        expr = fc.driver.expression
        if 'tan' not in expr and 'angle' not in expr:
            continue
        print(f"\n  [{label}] {id_block.name}")
        print(f"    驱动路径 : {fc.data_path}[{fc.array_index}]")
        print(f"    表达式   : {expr}")
        for var in fc.driver.variables:
            for tgt in var.targets:
                id_name = tgt.id.name if tgt.id else 'None'
                print(f"    变量 {var.name}: id={id_name}, path={tgt.data_path}")
                if tgt.id:
                    try:
                        val = tgt.id.path_resolve(tgt.data_path)
                        print(f"      当前值: {val}")
                        if isinstance(val, (int, float)):
                            if val == 0:
                                print(f"      >>> 除零！angle=0 时 tan(0/2)=0 <<<")
                            angle_deg = math.degrees(val) if 'angle' in var.name.lower() else None
                            if angle_deg is not None:
                                print(f"      角度: {angle_deg:.4f} deg")
                    except Exception as e:
                        print(f"      解析失败: {e}")

# 扫描所有 Object
for obj in bpy.data.objects:
    scan_drivers(obj, f"Object:{obj.type}")
    # 扫描 Object Data (Camera/Mesh/etc.)
    if obj.data:
        scan_drivers(obj.data, f"Data:{obj.type}")

# ──────────────────────────────────────────────
# [2] 所有相机状态
# ──────────────────────────────────────────────
print(f"\n[2] 所有相机状态")
print(SUB)

for obj in bpy.data.objects:
    if obj.type != 'CAMERA':
        continue
    cam = obj.data
    print(f"\n  相机: {obj.name}  (data: {cam.name})")
    print(f"    type        : {cam.type}          # PERSP=透视, ORTHO=正交")
    print(f"    lens        : {cam.lens:.4f} mm")
    print(f"    angle       : {cam.angle:.6f} rad ({math.degrees(cam.angle):.4f} deg)")
    print(f"    sensor_width: {cam.sensor_width:.2f} mm")
    print(f"    sensor_fit  : {cam.sensor_fit}")
    # 关键: lens==0 或 NaN
    if cam.lens == 0:
        print(f"    >>> lens=0！渲染会异常 <<<")
    if math.isnan(cam.lens) or math.isinf(cam.lens):
        print(f"    >>> lens=NaN/Inf！driver 求值失败 <<<")

# ──────────────────────────────────────────────
# [3] 场景活跃相机 & Markers
# ──────────────────────────────────────────────
print(f"\n[3] 场景活跃相机 & Timeline Markers")
print(SUB)

scene = bpy.context.scene
print(f"  Scene           : {scene.name}")
print(f"  Active camera   : {scene.camera.name if scene.camera else '>>> None！未设置活跃相机 <<<'}")
print(f"  Frame range     : {scene.frame_start} - {scene.frame_end}")
print(f"  Current frame   : {scene.frame_current}")

if scene.timeline_markers:
    print(f"\n  Timeline markers:")
    for m in scene.timeline_markers:
        cam_name = m.camera.name if m.camera else 'None'
        print(f"    Frame {m.frame:>5}: {m.name}  camera={cam_name}")
else:
    print("  无 timeline markers")

# ──────────────────────────────────────────────
# [4] 循环依赖检查（lens ↔ angle）
# ──────────────────────────────────────────────
print(f"\n[4] 循环依赖检查 (lens ↔ angle)")
print(SUB)

found_cycle = False
for obj in bpy.data.objects:
    if obj.type != 'CAMERA':
        continue
    cam = obj.data
    ad = cam.animation_data
    if not ad or not ad.drivers:
        continue
    for fc in ad.drivers:
        for var in fc.driver.variables:
            for tgt in var.targets:
                if tgt.id == cam:
                    # driver 在 cam 上，变量也引用 cam 自身
                    if fc.data_path == 'lens' and 'angle' in tgt.data_path:
                        print(f"  >>> 循环依赖: {obj.name}")
                        print(f"      driver 挂在 'lens' 上，却读取自身 'angle'")
                        print(f"      lens 和 angle 是同一属性的两个表示，互相引用构成循环！")
                        print(f"      GUI 中用缓存值侥幸通过，CLI(-b) 中初始 angle 可能为 0 → 除零")
                        found_cycle = True
                    elif fc.data_path == 'angle' and 'lens' in tgt.data_path:
                        print(f"  >>> 循环依赖: {obj.name} (angle←lens)")
                        found_cycle = True

if not found_cycle:
    print("  未检测到 lens↔angle 循环（但 angle 变量可能引用其他来源，见 [1]）")

# ──────────────────────────────────────────────
# [5] 手动模拟 driver 求值
# ──────────────────────────────────────────────
print(f"\n[5] 手动模拟 driver 求值")
print(SUB)

for obj in bpy.data.objects:
    if obj.type != 'CAMERA':
        continue
    cam = obj.data
    ad = cam.animation_data
    if not ad or not ad.drivers:
        continue
    for fc in ad.drivers:
        if 'tan' not in fc.driver.expression:
            continue
        print(f"\n  相机: {obj.name}")
        print(f"    表达式: {fc.driver.expression}")
        print(f"    驱动属性: {fc.data_path}")

        # 收集变量值
        var_vals = {}
        for var in fc.driver.variables:
            for tgt in var.targets:
                if tgt.id:
                    try:
                        val = tgt.id.path_resolve(tgt.data_path)
                        var_vals[var.name] = val
                        print(f"    {var.name} = {val}")
                    except:
                        var_vals[var.name] = None
                        print(f"    {var.name} = <无法解析>")

        # 尝试计算
        angle = var_vals.get('angle')
        if angle is not None:
            half = angle / 2
            t = math.tan(half)
            if t == 0:
                print(f"    tan({half}) = {t}  →  除零！")
                print(f"    结果会是 inf/NaN，lens 被设为无效值")
            else:
                result = 24.0 / t / 2
                print(f"    tan({half:.6f}) = {t:.6f}")
                print(f"    24.0 / {t:.6f} / 2 = {result:.4f} mm")
                print(f"    当前 lens = {cam.lens:.4f} mm")
                if abs(result - cam.lens) > 0.01:
                    print(f"    >>> 计算值与当前 lens 不一致，driver 可能未正确求值 <<<")

# ──────────────────────────────────────────────
# [6] 检查 camera type / lens 是否有 keyframe
# ──────────────────────────────────────────────
print(f"\n[6] Camera 动画 (keyframe) 检查")
print(SUB)

for obj in bpy.data.objects:
    if obj.type != 'CAMERA':
        continue
    cam = obj.data
    ad = cam.animation_data
    if ad and ad.action:
        for fc in ad.action.fcurves:
            if any(k in fc.data_path for k in ('type', 'lens', 'angle', 'ortho_scale')):
                print(f"  {obj.name}: {fc.data_path} — {len(fc.keyframe_points)} 个关键帧")
                for kp in fc.keyframe_points[:5]:
                    print(f"    frame {kp.co.x:.0f}: {kp.co.y:.4f}")

# ──────────────────────────────────────────────
# [7] 渲染前强制更新 depsgraph
# ──────────────────────────────────────────────
print(f"\n[7] 强制更新 depsgraph")
print(SUB)
bpy.context.view_layer.update()
print("  depsgraph 已更新，重新检查 lens 值:")
for obj in bpy.data.objects:
    if obj.type == 'CAMERA':
        print(f"  {obj.name}: lens={obj.data.lens:.4f}, angle={obj.data.angle:.6f}, type={obj.data.type}")

print(f"\n{SEP}")
print("调试完成。请检查以上输出中:")
print("  1. angle 变量当前值是否为 0（导致除零）")
print("  2. 是否存在 lens↔angle 循环依赖")
print("  3. 场景活跃相机是否正确")
print("  4. camera type 是 PERSP 还是 ORTHO")
print(SEP)
