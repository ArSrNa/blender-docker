"""
Blender CLI 渲染前的相机修复脚本

用法:
  blender -b your_file.blend --python fix_camera_cli.py -o output/60-100/####.png -s 60 -e 120 -a

功能:
  1. 确保场景有活跃相机
  2. 强制相机类型为 PERSP
  3. 修复 driver 除零（在表达式中加保护）
  4. 强制更新 depsgraph
"""

import bpy
import math

print("=" * 50)
print("Camera Fix Script (CLI pre-render)")
print("=" * 50)

scene = bpy.context.scene

# ── 1. 确保有活跃相机 ──
if not scene.camera:
    # 找第一个相机
    for obj in bpy.data.objects:
        if obj.type == 'CAMERA':
            scene.camera = obj
            print(f"设置活跃相机: {obj.name}")
            break

if not scene.camera:
    raise RuntimeError("场景中没有相机！无法渲染。")

cam_obj = scene.camera
cam = cam_obj.data
print(f"活跃相机: {cam_obj.name}")
print(f"  修改前: type={cam.type}, lens={cam.lens}, angle={cam.angle}")

# ── 2. 强制 PERSP ──
if cam.type != 'PERSP':
    cam.type = 'PERSP'
    print(f"  已将 type 从 ORTHO 改为 PERSP")

# ── 3. 修复 driver 表达式（加除零保护）──
def fix_driver_expr(ad):
    if not ad or not ad.drivers:
        return 0
    count = 0
    for fc in ad.drivers:
        expr = fc.driver.expression
        if 'tan' in expr and '/' in expr:
            # 在 tan() 外面包一层 max(..., 0.0001) 防止除零
            # 只做简单替换: tan(X) → max(tan(X), 0.0001)
            import re
            # 匹配 tan(...) 模式
            new_expr = re.sub(
                r'tan\(([^)]+)\)',
                r'max(tan(\1), 0.0001)',
                expr
            )
            # 防止重复替换
            if new_expr != expr and 'max(tan' not in expr:
                fc.driver.expression = new_expr
                print(f"  修复 driver: {expr} → {new_expr}")
                count += 1
    return count

fixed = fix_driver_expr(cam.animation_data)
fixed += fix_driver_expr(cam_obj.animation_data)
if fixed == 0:
    print("  未发现需要修复的 driver（或已修复过）")

# ── 4. 强制 depsgraph 更新 ──
bpy.context.view_layer.update()
print(f"  修改后: type={cam.type}, lens={cam.lens}, angle={cam.angle}")
print("=" * 50)
