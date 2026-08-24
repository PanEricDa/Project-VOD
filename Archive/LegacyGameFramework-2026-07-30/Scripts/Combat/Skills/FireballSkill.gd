class_name FireballSkill
extends SkillModuleBase

## 投射物成功进入飞行状态后发送；失败实例绝不会通过该信号暴露给外部。
signal projectile_launched(projectile: Node3D)
## 原样转发每个投射物报告的碰撞位置。
signal projectile_impacted(position: Vector3)
## 原样转发每个投射物报告的直接命中信息，本模块不处理目标数值。
signal fireball_hit(
	target: CharacterBody3D,
	hit_position: Vector3,
	hit_direction: Vector3
)
## 原样转发每个投射物报告的范围结果，本模块不筛选或修改目标。
signal fireball_exploded(
	position: Vector3,
	targets: Array[CharacterBody3D]
)

const TARGET_HEIGHT_OFFSET: float = 0.25
const DIRECTION_EPSILON_SQUARED: float = 0.000001

@export_category("Projectile")
## 每次交付时实例化的新投射物场景；实例生命周期归当前游戏场景所有。
@export var projectile_scene: PackedScene
## 施法起点必须解析为已进入场景树的 Marker3D。
@export_node_path("Marker3D") var cast_origin_path: NodePath = ^"CastOrigin"
## 投射物直线飞行速度，单位为米每秒。
@export_range(0.1, 30.0, 0.1) var projectile_speed: float = 9.0
## 投射物每秒允许的最大追踪转角，单位为度。
@export_range(0.0, 1080.0, 1.0) var turn_speed_degrees: float = 180.0
## 投射物未命中时的最长存活时间，单位为秒。
@export_range(0.1, 30.0, 0.1) var maximum_lifetime: float = 3.0
## 命中后用于投射物自身范围查询的半径，单位为米。
@export_range(0.0, 10.0, 0.05) var explosion_radius: float = 1.2


func _ready() -> void:
	super._ready()
	# 仅监听父类生命周期，不改写父类的计时、状态转换或冷却规则。
	# 同一模块卸载后重新进入场景树时连接仍然存在，因此逐项检查以避免重复连接错误。
	if not cast_started.is_connected(_on_cast_started):
		cast_started.connect(_on_cast_started)
	if not delivery_requested.is_connected(_on_delivery_requested):
		delivery_requested.connect(_on_delivery_requested)
	if not cast_cancelled.is_connected(_on_cast_cancelled):
		cast_cancelled.connect(_on_cast_cancelled)
	if not cast_failed.is_connected(_on_cast_failed):
		cast_failed.connect(_on_cast_failed)
	if not module_reset.is_connected(_on_module_reset):
		module_reset.connect(_on_module_reset)


## 验证依赖、在明确的当前游戏场景下创建投射物，并仅在 launch 成功后报告交付成功。
func deliver_skill(
	caster: Node3D,
	target: Node3D,
	_target_position: Vector3
) -> bool:
	# 直接调用公开交付接口时也先关闭蓄力，保证视觉交接与父类信号路径一致。
	_stop_charge_effect()
	if projectile_scene == null:
		return false
	var cast_origin := get_node_or_null(cast_origin_path) as Marker3D
	if cast_origin == null or not cast_origin.is_inside_tree():
		return false
	if not is_instance_valid(caster) or not caster.is_inside_tree():
		return false
	var enemy_target := target as CharacterBody3D
	if (
		enemy_target == null
		or not is_instance_valid(enemy_target)
		or not enemy_target.is_inside_tree()
		or not enemy_target.is_in_group(&"enemy_targets")
	):
		return false
	var scene_tree := get_tree()
	if scene_tree == null:
		return false
	var gameplay_parent := scene_tree.current_scene
	if gameplay_parent == null or not gameplay_parent.is_inside_tree():
		return false
	if not _launch_parameters_are_valid():
		return false

	var aim_offset: Vector3 = (
		enemy_target.global_position
		+ Vector3.UP * TARGET_HEIGHT_OFFSET
		- cast_origin.global_position
	)
	if not aim_offset.is_finite() or aim_offset.length_squared() <= DIRECTION_EPSILON_SQUARED:
		return false
	var initial_direction: Vector3 = aim_offset.normalized()

	var instance := projectile_scene.instantiate()
	var projectile := instance as Node3D
	if projectile == null:
		_free_failed_instance(instance)
		return false
	if not _has_launch_method_contract(projectile) or not _has_projectile_signal_contract(projectile):
		projectile.free()
		return false

	# 先进入当前游戏场景，再调用 launch，确保投射物可安全读取物理世界与全局变换。
	gameplay_parent.add_child(projectile)
	var launch_result: Variant = projectile.call(
		"launch",
		caster,
		enemy_target,
		cast_origin.global_position,
		initial_direction,
		projectile_speed,
		turn_speed_degrees,
		maximum_lifetime,
		explosion_radius
	)
	if (
		launch_result is not bool
		or not bool(launch_result)
		or not is_instance_valid(projectile)
		or projectile.is_queued_for_deletion()
		or not projectile.is_inside_tree()
		or projectile.get_parent() != gameplay_parent
	):
		if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
			projectile.queue_free()
		return false

	# 绑定实例 ID 而非保存投射物成员引用；节点退出时其信号连接会自动解除。
	var source_id: int = projectile.get_instance_id()
	projectile.projectile_impacted.connect(_on_projectile_impacted.bind(source_id))
	projectile.fireball_hit.connect(_on_fireball_hit.bind(source_id))
	projectile.fireball_exploded.connect(_on_fireball_exploded.bind(source_id))
	projectile_launched.emit(projectile)
	return true


## 所有浮点参数必须有限，并满足真实投射物 launch 接口的取值约束。
func _launch_parameters_are_valid() -> bool:
	return (
		is_finite(projectile_speed)
		and projectile_speed > 0.0
		and is_finite(turn_speed_degrees)
		and turn_speed_degrees >= 0.0
		and is_finite(maximum_lifetime)
		and maximum_lifetime > 0.0
		and is_finite(explosion_radius)
		and explosion_radius >= 0.0
	)


## launch 必须公开恰好八个参数；提前拒绝错误参数个数，避免动态 call 产生运行时错误。
func _has_launch_method_contract(projectile: Node3D) -> bool:
	if not projectile.has_method(&"launch"):
		return false
	for method_data: Dictionary in projectile.get_method_list():
		if StringName(method_data.get("name", &"")) != &"launch":
			continue
		var arguments: Array = method_data.get("args", [])
		var expected_arguments: Array = [
			[TYPE_OBJECT, &"Node3D", PROPERTY_HINT_NONE, ""],
			[TYPE_OBJECT, &"CharacterBody3D", PROPERTY_HINT_NONE, ""],
			[TYPE_VECTOR3, &"", PROPERTY_HINT_NONE, ""],
			[TYPE_VECTOR3, &"", PROPERTY_HINT_NONE, ""],
			[TYPE_FLOAT, &"", PROPERTY_HINT_NONE, ""],
			[TYPE_FLOAT, &"", PROPERTY_HINT_NONE, ""],
			[TYPE_FLOAT, &"", PROPERTY_HINT_NONE, ""],
			[TYPE_FLOAT, &"", PROPERTY_HINT_NONE, ""],
		]
		var return_data: Dictionary = method_data.get("return", {})
		return (
			_argument_metadata_matches(arguments, expected_arguments)
			and int(return_data.get("type", TYPE_NIL)) == TYPE_BOOL
			and StringName(return_data.get("class_name", &"")) == &""
			and (method_data.get("default_args", []) as Array).is_empty()
		)
	return false


## 转发信号的参数数量、顺序、对象类型和 typed Array 元数据必须与公开契约完全一致。
func _has_projectile_signal_contract(projectile: Node3D) -> bool:
	var expected_contracts := {
		&"projectile_impacted": [
			[TYPE_VECTOR3, &"", PROPERTY_HINT_NONE, ""],
		],
		&"fireball_hit": [
			[TYPE_OBJECT, &"CharacterBody3D", PROPERTY_HINT_NONE, ""],
			[TYPE_VECTOR3, &"", PROPERTY_HINT_NONE, ""],
			[TYPE_VECTOR3, &"", PROPERTY_HINT_NONE, ""],
		],
		&"fireball_exploded": [
			[TYPE_VECTOR3, &"", PROPERTY_HINT_NONE, ""],
			[TYPE_ARRAY, &"", PROPERTY_HINT_ARRAY_TYPE, "CharacterBody3D"],
		],
	}
	var signal_list: Array[Dictionary] = projectile.get_signal_list()
	for signal_name: StringName in expected_contracts:
		var signal_data := _find_named_metadata(signal_list, signal_name)
		if signal_data.is_empty():
			return false
		if not _argument_metadata_matches(
			signal_data.get("args", []),
			expected_contracts[signal_name]
		):
			return false
		if not (signal_data.get("default_args", []) as Array).is_empty():
			return false
	return true


## 比较 Godot 4.7 暴露的 Variant 类型、对象 class_name、hint 与 hint_string。
func _argument_metadata_matches(arguments: Array, expected: Array) -> bool:
	if arguments.size() != expected.size():
		return false
	for index: int in expected.size():
		var argument: Dictionary = arguments[index]
		var expected_argument: Array = expected[index]
		if int(argument.get("type", TYPE_NIL)) != int(expected_argument[0]):
			return false
		if StringName(argument.get("class_name", &"")) != StringName(expected_argument[1]):
			return false
		if int(argument.get("hint", PROPERTY_HINT_NONE)) != int(expected_argument[2]):
			return false
		if str(argument.get("hint_string", "")) != str(expected_argument[3]):
			return false
	return true


## 按名称提取方法或信号元数据；未找到时返回空字典并由调用方安全拒绝。
func _find_named_metadata(entries: Array[Dictionary], metadata_name: StringName) -> Dictionary:
	for entry: Dictionary in entries:
		if StringName(entry.get("name", &"")) == metadata_name:
			return entry
	return {}


## 释放尚未加入场景树的错误类型实例；Resource 实例化理论上也可能返回非节点对象。
func _free_failed_instance(instance: Variant) -> void:
	if instance is Node:
		(instance as Node).free()


## 校验绑定来源仍是发信号的有效投射物，随后保持参数不变地向外发送。
func _on_projectile_impacted(impact_position: Vector3, source_id: int) -> void:
	if not is_instance_id_valid(source_id):
		return
	projectile_impacted.emit(impact_position)


## 每枚投射物的实例 ID 独立绑定，一个节点退出不会影响其他投射物连接。
func _on_fireball_hit(
	target: CharacterBody3D,
	hit_position: Vector3,
	hit_direction: Vector3,
	source_id: int
) -> void:
	if not is_instance_id_valid(source_id):
		return
	fireball_hit.emit(target, hit_position, hit_direction)


## 数组按投射物信号提供的原对象转发，不复制、不排序也不筛选。
func _on_fireball_exploded(
	explosion_position: Vector3,
	targets: Array[CharacterBody3D],
	source_id: int
) -> void:
	if not is_instance_id_valid(source_id):
		return
	fireball_exploded.emit(explosion_position, targets)


func _on_cast_started(_target: Node3D) -> void:
	var charge_effect := _get_charge_effect()
	if charge_effect != null and charge_effect.has_method(&"play"):
		charge_effect.call(&"play")


func _on_delivery_requested(_target: Node3D, _target_position: Vector3) -> void:
	_stop_charge_effect()


func _on_cast_cancelled(_target: Node3D) -> void:
	_stop_charge_effect()


func _on_cast_failed(_target: Node3D, _reason: StringName) -> void:
	_stop_charge_effect()


func _on_module_reset() -> void:
	_stop_charge_effect()


## 蓄力视觉是可选依赖；缺失节点、stop 或 reset_effect API 均不影响技能状态。
func _stop_charge_effect() -> void:
	var charge_effect := _get_charge_effect()
	if charge_effect == null:
		return
	if charge_effect.has_method(&"stop"):
		charge_effect.call(&"stop")
	elif charge_effect.has_method(&"reset_effect"):
		charge_effect.call(&"reset_effect")


func _get_charge_effect() -> Node:
	var cast_origin := get_node_or_null(cast_origin_path) as Marker3D
	if cast_origin == null:
		return null
	return cast_origin.get_node_or_null(^"FireballCastChargeEffect")


func _exit_tree() -> void:
	_stop_charge_effect()
	super._exit_tree()
