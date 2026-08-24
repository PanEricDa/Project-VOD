class_name AICrossbowAttack
extends AIAttackModuleBase

@export_category("Projectile")

## 发射帧实例化的投射物场景；当前默认配置为 Arrow.tscn。
@export var projectile_scene: PackedScene

## 单支箭从弩口抵达当前目标的固定飞行时长，单位为秒。
@export_range(0.01, 5.0, 0.01) var projectile_flight_duration: float = 0.30

## 箭矢轨迹中点在线性路径基础上额外抬升的高度，单位为米。
@export_range(0.0, 10.0, 0.05) var projectile_arc_height: float = 0.80

## 箭矢最终命中点相对目标根节点向上的偏移，单位为米。
@export_range(-5.0, 5.0, 0.05) var projectile_target_height_offset: float = 0.25

## 投射物异常存在时的保险销毁时间，避免无效箭矢长期残留。
@export_range(0.01, 30.0, 0.05) var projectile_maximum_lifetime: float = 2.0

## 武器模块内用于确定箭矢世界发射位置的 Marker3D 路径。
@export_node_path("Node3D") var attack_origin_path: NodePath = ^"WeaponPivot/AttackOrigin"

## 十字弓中装填箭矢的占位视觉路径；发射时隐藏，复位时恢复。
@export_node_path("Node3D") var loaded_projectile_visual_path: NodePath = ^"WeaponPivot/WeaponVisualRoot/CrossbowRoot/LoadedBolt"

## 记录当前普通攻击是否已经执行过发射帧，防止错误方法轨道重复生成箭矢。
var projectile_was_released: bool = false


## 只有父模块确认攻击成功开始后，才重置本轮发射标志和装填视觉。
func request_attack(target: CharacterBody3D) -> bool:
	var attack_started_successfully: bool = super.request_attack(target)
	if not attack_started_successfully:
		return false
	projectile_was_released = false
	_set_loaded_projectile_visible(true)
	return true


## 取消、卸装或脱战复位时恢复装填视觉，并允许下一轮攻击正常发射。
func reset_module() -> void:
	super.reset_module()
	projectile_was_released = false
	_set_loaded_projectile_visible(true)


## AnimationPlayer 方法轨道调用：从 AttackOrigin 生成且只生成一支独立箭矢。
## 箭矢加入当前场景而不是武器节点，因此不会继续继承 Ranger 的移动或旋转。
func _release_projectile() -> void:
	if attack_state != AttackState.ATTACKING or projectile_was_released:
		return
	projectile_was_released = true
	_set_loaded_projectile_visible(false)

	if projectile_scene == null:
		push_warning("AICrossbowAttack: projectile_scene is missing.")
		return
	if not is_instance_valid(current_target) or not current_target.is_inside_tree():
		return

	var origin: Node3D = get_node_or_null(attack_origin_path) as Node3D
	if origin == null:
		push_warning("AICrossbowAttack: attack_origin_path is invalid.")
		return

	var projectile: Node3D = projectile_scene.instantiate() as Node3D
	if projectile == null or not projectile.has_method("launch"):
		if projectile != null:
			projectile.queue_free()
		push_warning("AICrossbowAttack: projectile must be a Node3D with launch().")
		return

	var projectile_parent: Node = get_tree().current_scene
	if projectile_parent == null:
		projectile_parent = get_tree().root
	projectile_parent.add_child(projectile)
	if projectile.has_signal("projectile_hit"):
		projectile.connect(&"projectile_hit", _on_projectile_hit)

	var launched: bool = projectile.call(
		"launch",
		current_target,
		origin.global_position,
		projectile_flight_duration,
		projectile_arc_height,
		projectile_target_height_offset,
		projectile_maximum_lifetime
	) == true
	if not launched:
		projectile.queue_free()


## 将独立投射物的抵达事件转发为 AI 攻击模块统一命中接口。
## 即使射击动画已经结束，仍允许正在飞行的箭矢在抵达后发送本次命中。
func _on_projectile_hit(
	target: CharacterBody3D,
	hit_position: Vector3,
	hit_direction: Vector3
) -> void:
	attack_hit.emit(target, hit_position, hit_direction)


## 攻击动画完成后复用父类清理流程，并恢复下一轮的装填箭矢视觉。
func _on_animation_finished(animation_name: StringName) -> void:
	var finished_current_attack: bool = (
		attack_state == AttackState.ATTACKING
		and animation_name == attack_animation_name
	)
	super._on_animation_finished(animation_name)
	if finished_current_attack:
		projectile_was_released = false
		_set_loaded_projectile_visible(true)


## 安全切换装填箭矢的可见性；路径缺失只影响占位视觉，不阻止模块复位。
func _set_loaded_projectile_visible(visible_value: bool) -> void:
	var loaded_visual: Node3D = get_node_or_null(
		loaded_projectile_visual_path
	) as Node3D
	if loaded_visual != null:
		loaded_visual.visible = visible_value
