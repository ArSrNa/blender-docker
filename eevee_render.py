import bpy

bpy.context.scene.render.engine = 'BLENDER_EEVEE'
# 获取当前活动的场景
scene = bpy.context.scene
print(f"当前场景名称: {scene.name}")

# 设置输出分辨率
scene.render.resolution_x = 3840
scene.render.resolution_y = 1620
scene.render.resolution_percentage = 100

# 设置输出路径和格式
scene.render.filepath = "/workspace/data/output/####"
scene.render.image_settings.file_format = 'PNG'

# 渲染范围
scene.frame_start = 1000      # 起始帧
scene.frame_end = 1010       # 结束帧

# 因mmd插件在部分机器加载时变成了正交视角，这里强制转为透视
# 遍历场景中的所有对象
for obj in bpy.data.objects:
    # 检查对象是否为摄像机
    if obj.type == 'CAMERA':
        # 设置摄像机为透视视角
        obj.data.type = 'PERSP'
        print(f"摄像机 {obj.name} 已设置为透视视角。")


# 渲染动画（所有帧）
bpy.ops.render.render(animation=True, use_viewport=True)


# 或者渲染单帧
# bpy.ops.render.render(write_still=True)