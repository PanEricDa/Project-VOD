# 单体圣光回血特效设计

## 目标

创建一个只使用金白色视觉元素的单体治疗特效。效果附着在被治疗角色上，持续约 `0.5s`，通过地面光环、短促圣光柱、上升光点、四芒星闪光和轻微局部照明明确表达“圣光治疗生效”。

该效果只负责视觉播放，不修改生命值、不搜索治疗目标，也不依赖 Healer、StaffAttack 或具体治疗技能。未来任何治疗来源都可以实例化并调用同一接口。

## 视觉方向

整体颜色限制为：

- 暖金色：主要轮廓、光环和粒子。
- 象牙白：光柱主体和柔和高光。
- 高亮纯白：四芒星中心与极短峰值闪光。

不使用绿色、蓝色或其他治疗颜色。

效果阶段：

```text
0.00–0.08s：目标脚下的细薄金色圆环快速展开。
0.04–0.15s：金白色半透明光柱亮起并覆盖角色主体。
0.10–0.34s：少量金白光点围绕角色向上漂浮，身体中心闪现四芒星。
0.34–0.50s：光柱收束，光环、闪光和粒子迅速淡出。
```

节奏应短促、清晰，不形成持续施法或大型范围技能的观感。

## 场景结构

创建：

`res://Effects/Healing/HolyLightHealEffect.tscn`

建议结构：

```text
HolyLightHealEffect (Node3D)
├── GroundRing (MeshInstance3D)
├── LightColumn (MeshInstance3D)
├── RisingParticles (GPUParticles3D)
├── HealFlash (Node3D)
│   ├── VerticalRay (MeshInstance3D)
│   └── HorizontalRay (MeshInstance3D)
├── HealingLight (OmniLight3D)
└── AnimationPlayer
```

### GroundRing

- 使用水平放置的 `TorusMesh`。
- 材质为金色、透明、无阴影、加法或透明混合。
- 动画从较小缩放快速扩张至最终半径，同时降低透明度。
- 圆环只是视觉边界，不创建碰撞和范围判定。

### LightColumn

- 使用细长 `CylinderMesh`，底面位于角色脚底附近。
- 材质为象牙白到暖金色的半透明无阴影材质。
- 动画同时控制透明度与水平缩放：快速出现，短暂停留，然后收束淡出。
- 默认高度覆盖当前 `0.5m` 原型角色并留出顶部空间，但尺寸可在 Inspector 调整。

### RisingParticles

- 使用 `GPUParticles3D` 与小型发光 Quad 粒子。
- 粒子在角色周围的小圆柱体积内生成，具有轻微水平扩散和稳定向上速度。
- 单次发射，数量保持较少，避免 `0.5s` 效果显得杂乱。
- 粒子颜色只在金色与白色之间变化。

### HealFlash

- 使用两个细长 Quad 或 Box Mesh 交叉组成简化四芒星。
- 位于目标身体中心附近，始终面向当前摄像机或使用 billboard 材质。
- 在 `0.10–0.24s` 内快速放大、闪亮并淡出。
- 不使用医疗十字符号，避免与界面图标混淆。

### HealingLight

- 使用范围较小、能量较低的暖金白 `OmniLight3D`。
- 只在效果中段产生一次短促亮度脉冲。
- 默认能量需保守，不能明显改变整个场景曝光或照亮远处单位。

## 运行接口

创建：

`res://Effects/Healing/HolyLightHealEffect.gd`

公开信号：

```gdscript
signal effect_started()
signal effect_finished()
```

公开方法：

```gdscript
func play() -> void
func stop() -> void
func reset_effect() -> void
func is_playing() -> bool
```

行为规则：

- 默认进入场景树后自动播放。
- `play()` 从头重新播放；效果正在播放时再次调用会重置并重新开始，不创建重叠异步任务。
- `stop()` 立即停止并恢复所有节点初始隐藏状态，不发送 `effect_finished`。
- 自然播放到结尾时发送一次 `effect_finished`。
- `auto_free_on_finished=true` 时，发送完成信号后调用 `queue_free()`。
- `auto_free_on_finished=false` 时保留节点，供对象池或重复调用 `play()`。
- 节点退出场景树时停止动画与粒子，不残留局部灯光。

## Inspector 参数

脚本导出以下核心参数：

```gdscript
@export var autoplay: bool = true
@export var auto_free_on_finished: bool = true
@export_range(0.1, 2.0, 0.05) var effect_duration: float = 0.5

@export var primary_gold_color: Color
@export var ivory_light_color: Color
@export var highlight_color: Color

@export_range(0.1, 5.0, 0.05) var ring_radius: float = 0.65
@export_range(0.1, 5.0, 0.05) var column_height: float = 1.2
@export_range(0.05, 2.0, 0.05) var column_radius: float = 0.32
@export_range(1, 128, 1) var particle_amount: int = 18
@export_range(0.0, 10.0, 0.1) var light_energy: float = 1.2
@export_range(0.1, 10.0, 0.1) var light_range: float = 1.5
```

默认颜色建议：

```text
primary_gold_color = #FFD36A
ivory_light_color = #FFF4D6
highlight_color = #FFFFFF
```

`effect_duration` 改变时，内部动画按默认 `0.5s` 时间轴进行整体速度缩放，而不是要求用户逐项修改关键帧。

## 附着与坐标规则

- 效果场景实例应作为被治疗角色根节点或稳定视觉挂点的子节点。
- 根节点局部位置默认为 `Vector3.ZERO`，以角色脚底中心作为地面光环原点。
- 光柱和粒子使用局部坐标，因此目标移动时效果会一起移动，不会留在世界原地。
- 默认尺寸适配当前约 `0.5m` 高的原型单位；正式模型接入后只需调整导出尺寸或挂点。
- 特效不要求目标具有某个脚本、分组、碰撞层或生命组件。

## 材质与性能

- 仅使用 Godot 内建 Mesh、StandardMaterial3D、GPUParticles3D、OmniLight3D 和 AnimationPlayer。
- 不依赖外部图片、动画资产或第三方插件。
- 所有透明视觉关闭阴影投射。
- 默认单次粒子数约 `18`，局部灯光范围约 `1.5m`，适合少量单位同时触发。
- 当前不加入后处理、屏幕闪光、摄像机震动或全局环境亮度修改。

## 测试与验收

- 场景可独立实例化，不依赖 Healer 或 TestScene。
- 默认自动播放，总时长约 `0.5s`。
- 所有颜色均为金色、象牙白或纯白，不包含绿色元素。
- 地面光环、光柱、粒子、四芒星和局部灯光按时间顺序出现并完整淡出。
- `play()`、`stop()`、`reset_effect()` 和 `is_playing()` 接口可用。
- 重复调用 `play()` 不会叠加计时器或重复发送一次播放周期的完成信号。
- 关闭自动销毁后可以重复播放；启用时自然完成后只销毁一次。
- 修改持续时间、尺寸、粒子数量和灯光参数无需编辑脚本。
- Godot 4.7 Headless 加载和脚本编译无错误。
- 不修改或向 `Scenes/TestScene.tscn` 添加任何单位或特效实例；实际观察时可打开独立特效场景，或由用户手动把效果实例放入需要测试的角色。

## 暂缓范围

- 生命值恢复与治疗数值计算。
- Healer 技能选择、施法动作、目标选择和冷却。
- 治疗音效、数字跳字和 UI 提示。
- 正式纹理、复杂 Shader、体积光和后处理 Bloom 配置。
- 范围治疗、持续治疗、治疗链和复活效果。

