extends Node3D
## A/B比较专用控制台；试放仍调用真实执行组件/Host，不生成火球或执行DamageEffect。
## 日常战斗不使用本脚本。此场景冻结常规AI以隔离镜头差异，仍可使用1—4进行真实连携。
@export_category("Preview Assembly")
## 场景内真实执行组件，默认空不启用控制台，不修改正式技能资源。
@export var execution_source: SquadFinisherExecutionController
## 本场景已静态装配的Caster，默认空；切换模式只影响下一次试放。
@export var caster: AllyBase
## 预览敌人引用，用于重置生命和计算实际总伤害；默认空，不作为正式伤害目标列表。
@export var targets: Array[UnitBase] = []
## 本场景玩家引用，用于沿用既有锁定接口，默认空。
@export var player: PlayerBase

var _next_mode: int = 1
var _initial: Dictionary = {}
var _pause_token: int = 0
var _started_health: float = 0.0
var _last_damage: float = 0.0
var _world_probe: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for unit: UnitBase in targets:
		_initial[unit.get_instance_id()] = {"node":weakref(unit),"position":unit.global_position}
		unit.set_physics_process(false)
		unit.get_node("AITargetingComponent").debug_range_visible = false
	for actor: AllyBase in $Battle/SquadChainCommandController.companions:
		if not is_instance_valid(actor): continue
		actor.get_targeting_component().debug_range_visible = false
		actor.automatic_skill_cast_enabled = false
		actor.set_physics_process(false)
		# 预览将战斗房嵌套在控制台中，显式沿原Host接口绑定同一个Battle作用域。
		actor.get_node("SkillHost").configure_owner(actor, $Battle)
		_initial[actor.get_instance_id()] = {"node":weakref(actor),"position":actor.global_position}
	for pair in [[$UI/Panel/ModeA,0],[$UI/Panel/ModeB,1]]:
		pair[0].pressed.connect(func() -> void: _next_mode = pair[1])
	$UI/Panel/Cast.pressed.connect(try_cast)
	$UI/Panel/Reset.pressed.connect(reset_preview)
	$UI/Panel/Pause.pressed.connect(_toggle_pause)
	if is_instance_valid(execution_source):
		execution_source.execution_ended.connect(_on_execution_ended)
	reset_preview()

func _physics_process(delta: float) -> void:
	if get_tree().paused: return
	for actor: AllyBase in $Battle/SquadChainCommandController.companions:
		if not is_instance_valid(actor): continue
		var host := actor.get_node("SkillHost") as SkillHostComponent
		if host.has_pending_command() or host.has_command_action_lock():
			actor.get_behavior_state_machine().physics_tick(delta)

func _process(delta: float) -> void:
	if not is_instance_valid(execution_source): return
	if not get_tree().paused:
		_world_probe += delta
		$Battle/WorldTimeProbe.rotation.y += delta * 2.0
	var status := execution_source.get_execution_status()
	var mode := "A · 首发恢复" if _next_mode == 0 else "B · 轰炸完成后恢复"
	$UI/Panel/Mode.text = "下次：" + mode
	$UI/Panel/Status.text = "阶段：%s\n世界速度：%.1f%%    世界计时：%.2fs\n发射：%d/5  落地：%d/5\n主爆炸待办：%d  总伤害：%.1f\n结束原因：%s" % [status.phase, Engine.time_scale * 100, _world_probe, status.launched, status.landed, status.main_effects_pending, _last_damage if status.phase == &"idle" else maxf(_started_health - _total_health(),0),status.reason]
	$UI/Panel/Cast.disabled = status.phase != &"idle" or get_tree().paused or execution_source.get_actor_availability(caster) != &""

## 以固定本地种子走真实终结入口，不写共享资源；true只表示受理，不代表所有火球命中。
func try_cast() -> bool:
	if not is_instance_valid(execution_source) or get_tree().paused: return false
	_started_health = _total_health()
	_last_damage = 0.0
	return execution_source.begin_finisher(caster, 171018, _next_mode)

## 停止本预览旧交付，恢复相同位置/生命及锁定；只改变预览实例，不保存正式场景/资源。
func reset_preview() -> void:
	if is_instance_valid(execution_source):
		execution_source.cancel_execution(&"preview_reset")
	for record: Dictionary in _initial.values():
		var unit := record.node.get_ref() as UnitBase
		if not is_instance_valid(unit): continue
		if unit is AllyBase:
			var host := unit.get_node("SkillHost") as SkillHostComponent
			host.cancel_active_skill(&"preview_reset")
			if host.get_finisher_skill() != null: host.get_finisher_skill().reset_skill()
			unit.get_combat_system().cancel_current_action()
		if unit.is_dead(): unit.revive(unit.get_maximum_health())
		else: unit.apply_healing(unit.get_maximum_health())
		unit.global_position = record.position
		unit.velocity = Vector3.ZERO
		unit.reset_physics_interpolation()
	if is_instance_valid(player) and not targets.is_empty() and is_instance_valid(targets[0]):
		player.get_node(PlayerBase.TARGETING_SYSTEM_PATH).request_lock(targets[0])
		caster.get_targeting_component().call("_set_locked_target", targets[0])
	_started_health = _total_health()
	_last_damage = 0.0

func _total_health() -> float:
	var amount := 0.0
	for unit: UnitBase in targets:
		if is_instance_valid(unit): amount += unit.get_current_health()
	return amount

func _on_execution_ended(_status: Dictionary) -> void:
	_last_damage = maxf(_started_health - _total_health(), 0.0)

func _toggle_pause() -> void:
	var pause := $Battle/ChainSkillPresentationController/PauseCoordinator as GamePauseCoordinator
	if $UI/Panel/Pause.button_pressed:
		_pause_token = pause.acquire_pause(execution_source, &"preview_menu")
	else:
		pause.release_pause(_pause_token)
		_pause_token = 0
	$UI/Panel/Pause.text = "继续（真暂停）" if $UI/Panel/Pause.button_pressed else "暂停（真暂停）"
