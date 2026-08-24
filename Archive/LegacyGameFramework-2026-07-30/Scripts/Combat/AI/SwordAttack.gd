class_name AISwordAttack
extends AIAttackModuleBase

## Warrior 长剑普通攻击模块。
##
## 该模块只负责从场景声明的有效攻击动画中按“随机袋”选择下一招；攻击状态、
## 信号、Hitbox 命中窗口和命中反馈生命周期继续由 AIAttackModuleBase 统一管理。

@export_category("Sword Animations")
## 可参与随机选择的候选动画。空名称、不存在的动画和重复名称会被自动忽略。
@export var attack_animation_names: Array[StringName] = [
	&"attack_1",
	&"attack_2",
	&"attack_3"
]

## 当前尚未抽取的动画。每次补袋时，每个有效动画只加入一次并整体洗牌。
var animation_bag: Array[StringName] = []

## 上一次成功选出的动画，用于阻止两个随机袋交界处连续出现同一招。
var last_selected_animation: StringName = &""

## 记录本轮无有效动画配置是否已经告警，避免 AllyBase 每帧请求时刷屏。
var missing_animation_warning_emitted: bool = false


## 仅当公共攻击前置条件成立，且候选列表中至少存在一个真实动画时才可攻击。
## 这里不调用父类 can_attack()，因为父类会检查默认的单个 attack 动画名称，
## 而长剑必须依据 attack_animation_names 的去重有效集合判断。
func can_attack() -> bool:
	var valid_animation_names: Array[StringName] = _get_valid_animation_names()
	if valid_animation_names.is_empty():
		_warn_if_no_valid_animation()
		return false

	# 一旦配置恢复有效，清除告警锁；未来若再次失效，可以重新告警一次。
	missing_animation_warning_emitted = false
	return (
		attack_state == AttackState.IDLE
		and attack_profile != null
		and attack_animation_player != null
	)


## 验证模块与目标后才触碰随机袋，失败请求不会改变后续动画选择顺序。
## 选出动画后交给父类开始攻击，以复用公共状态、信号、Hitbox 与反馈生命周期。
func request_attack(target: CharacterBody3D) -> bool:
	if not can_attack():
		return false
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false

	var valid_animation_names: Array[StringName] = _get_valid_animation_names()
	_prune_animation_bag(valid_animation_names)
	if animation_bag.is_empty():
		_refill_animation_bag()
	if animation_bag.is_empty():
		_warn_if_no_valid_animation()
		return false

	var selected_animation: StringName = animation_bag.pop_back()
	attack_animation_name = selected_animation
	last_selected_animation = selected_animation
	return super.request_attack(target)


## 从 Inspector 候选中生成当前有效的唯一动画列表，并保留首次出现的顺序。
func _get_valid_animation_names() -> Array[StringName]:
	var valid_animation_names: Array[StringName] = []
	if attack_animation_player == null:
		return valid_animation_names

	var seen_animation_names: Dictionary = {}
	for animation_name: StringName in attack_animation_names:
		if animation_name == &"":
			continue
		if seen_animation_names.has(animation_name):
			continue
		if not attack_animation_player.has_animation(animation_name):
			continue
		seen_animation_names[animation_name] = true
		valid_animation_names.append(animation_name)
	return valid_animation_names


## 用当前有效唯一动画重新装满并洗牌。
## pop_back() 会选择袋尾；若袋尾等于上一招，则与另一项交换，避免跨袋连招。
func _refill_animation_bag() -> void:
	animation_bag = _get_valid_animation_names()
	animation_bag.shuffle()
	if (
		animation_bag.size() > 1
		and animation_bag.back() == last_selected_animation
	):
		var bag_end_index: int = animation_bag.size() - 1
		var replacement_index: int = randi_range(0, bag_end_index - 1)
		var replacement_animation: StringName = animation_bag[replacement_index]
		animation_bag[replacement_index] = animation_bag[bag_end_index]
		animation_bag[bag_end_index] = replacement_animation


## Inspector 配置可能在运行时改变；消费前移除已失效项，保证袋中始终只有有效动画。
func _prune_animation_bag(valid_animation_names: Array[StringName]) -> void:
	for bag_index: int in range(animation_bag.size() - 1, -1, -1):
		if animation_bag[bag_index] not in valid_animation_names:
			animation_bag.remove_at(bag_index)


## 同一段无有效动画的时期只告警一次；恢复有效配置后由 can_attack() 解锁。
func _warn_if_no_valid_animation() -> void:
	if missing_animation_warning_emitted:
		return
	missing_animation_warning_emitted = true
	push_warning(
		"AISwordAttack: attack_animation_names does not contain any unique, "
		+ "non-empty animation available in AttackAnimationPlayer."
	)
