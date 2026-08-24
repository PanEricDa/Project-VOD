extends "res://Scripts/AI/AllyBase.gd"

## Mage 专用的编队协调脚本。
## 通用移动、游荡、冲刺和区域重选仍由 AllyBase 负责；本脚本只决定 Mage 应锁定哪一侧。

@export_category("Mage Formation Coordination")
## 作为 Mage 选侧参照的 Ranger 节点路径。
## 默认结构适用于 TestScene：Mage 与 Ranger 均为场景根节点的直接子节点。
@export_node_path("CharacterBody3D") var ranger_path: NodePath = ^"../Ranger"

## 缓存 Ranger 引用，用于接收权威侧向变化信号。
var ranger_reference: CharacterBody3D


## Mage 进入场景时先连接 Ranger 的侧向信号，再执行父类初始化。
## 即使 Ranger 已经先完成初始化，父类首次选侧仍会通过 _choose_locked_side 读取其当前值。
func _ready() -> void:
	ranger_reference = get_node_or_null(ranger_path) as CharacterBody3D
	if ranger_reference != null and ranger_reference.has_signal("formation_side_changed"):
		var side_changed_callable: Callable = Callable(self, "_on_ranger_formation_side_changed")
		if not ranger_reference.is_connected("formation_side_changed", side_changed_callable):
			ranger_reference.connect("formation_side_changed", side_changed_callable)

	super._ready()


## 每当父类首次选择侧向，或确认离开原编队区域并重新选侧时，都会调用此方法。
## Ranger 已经锁定左侧或右侧时，Mage 始终返回相反方向，从而避免两个远程职业挤在同侧。
## 如果 Ranger 尚未就绪、路径无效或尚未完成选侧，则回退到父类的随机逻辑，保证 Mage 仍可正常运行。
func _choose_locked_side() -> int:
	if ranger_reference == null:
		ranger_reference = get_node_or_null(ranger_path) as CharacterBody3D
	if ranger_reference == null:
		return super._choose_locked_side()

	var ranger_side_value: Variant = ranger_reference.get("locked_side")
	if ranger_side_value is int:
		var ranger_side: int = int(ranger_side_value)
		if ranger_side == -1 or ranger_side == 1:
			return -ranger_side

	return super._choose_locked_side()


## Ranger 每次重新选侧后立即同步 Mage，而不等待 Mage 自己离开区域或计时结束。
## 通过 AllyBase 的统一入口同时更新侧向、区域状态和游荡目标，确保两端维护规则完全一致。
func _on_ranger_formation_side_changed(ranger_side: int) -> void:
	if ranger_side != -1 and ranger_side != 1:
		return

	_apply_locked_side(-ranger_side, true)
