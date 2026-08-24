class_name CharacterAnimationEventPlayer
extends AnimationPlayer

## 角色动画方法轨道与游戏逻辑之间的轻量事件桥。
##
## AnimationLibrary 只调用无参数方法，不直接访问 PlayerBase、武器数据或物理移动。
## 玩家与未来 AI 控制器可以分别监听信号，并按照各自规则决定是否执行请求。

## 当前攻击动画到达位移 marker 时发出。
signal attack_motion_requested()
## 当前攻击动画到达近战判定开始 marker 时发出。
signal hit_window_open_requested()
## 当前攻击动画到达近战判定结束 marker 时发出。
signal hit_window_close_requested()
## 当前攻击动画到达远程投射物释放 marker 时发出。
signal projectile_release_requested()
## 通用角色动作到达“交付”时间点时发出。
##
## 该事件不关心交付的是投射物、治疗还是其他技能效果，因此玩家与 AI
## 都可以通过同一条动画契约消费它。
signal action_release_requested()
## 通用角色动作完成其逻辑占用时间点时发出。
signal action_finish_requested()
signal death_animation_finished_requested()


func _ready() -> void:
	# 动作方法标记承担交付时机契约，必须在 AnimationPlayer 推进到该关键帧时
	# 同步发出，避免延后一帧造成投射物、命中窗口或施法完成状态错位。
	callback_mode_method = (
		AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	)


## 供 AnimationPlayer 方法轨道调用的稳定入口。
##
## 方法轨道只负责标记动画时间点；距离与速度由装备的 WeaponData 提供。
func request_attack_motion() -> void:
	attack_motion_requested.emit()


## 供方法轨道标记近战判定开始；具体武器与连击段由攻击控制器补充。
func open_attack_hit_window() -> void:
	hit_window_open_requested.emit()


## 供方法轨道标记近战判定结束；事件桥本身不持有检测状态。
func close_attack_hit_window() -> void:
	hit_window_close_requested.emit()


## 供远程武器动画的方法轨道调用。
## 该方法只标记发射时机，目标、投射物实例化与命中逻辑由 AI 远程战斗组件负责。
func release_projectile() -> void:
	projectile_release_requested.emit()


## 供技能/动作动画的方法轨道调用，标记动作已经到达实际交付时间点。
func release_action() -> void:
	action_release_requested.emit()


## 供技能/动作动画的方法轨道调用，标记控制器可以释放当前动作占用。
func finish_action() -> void:
	action_finish_requested.emit()


func play_named_animation(library_name: StringName, animation_name: StringName) -> bool:
	var full_name := StringName("%s/%s" % [library_name, animation_name])
	if not has_animation(full_name):
		push_warning("CharacterAnimationEventPlayer: animation '" + str(full_name) + "' NOT FOUND. Available: " + str(get_animation_list()))
		return false
	play(full_name)
	return true


func play_unit_animation(animation_name: StringName) -> bool:
	return play_named_animation(&"unit", animation_name)


func finish_death_animation() -> void:
	death_animation_finished_requested.emit()


func reset_unit_animation() -> void:
	stop()
	play_named_animation(&"unit", &"RESET")
