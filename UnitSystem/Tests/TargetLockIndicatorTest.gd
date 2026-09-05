extends SceneTree

## 验证 TargetLockIndicator 三状态（进入/维持/退出）与位置语义的独立行为契约。
## 测试直接实例化脚本节点，不加载玩家、敌人或测试房间，也不依赖正式网格与材质。
## 状态断言使用 EffectState 的声明顺序数值（ENTER=0, MAINTAIN=1, EXIT=2），
## 与计划锁定的稳定接口一致；所有交互通过公开方法完成，不访问私有字段。

const INDICATOR_SCRIPT_PATH := (
	"res://UnitSystem/Visuals/Targeting/TargetLockIndicator.gd"
)
## 无头环境下推进动画的计时安全余量，单位为秒。
const TIME_MARGIN := 0.08
## 与 EffectState 枚举声明顺序一一对应的状态数值。
const STATE_ENTER := 0
const STATE_MAINTAIN := 1
const STATE_EXIT := 2

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var indicator_script := load(INDICATOR_SCRIPT_PATH) as GDScript
	_expect(indicator_script != null, "TargetLockIndicator script exists")
	if indicator_script == null:
		_finish()
		return
	var indicator := indicator_script.new() as Node3D
	_expect(indicator != null, "TargetLockIndicator instantiates as Node3D")
	if indicator == null:
		_finish()
		return
	root.add_child(indicator)
	await process_frame

	_expect(not indicator.visible, "fresh indicator stays hidden")
	_expect(
		not bool(indicator.call(&"is_effect_visible")),
		"hidden indicator reports no visible effect"
	)

	var maintain_opacity := float(indicator.get("maintain_opacity"))
	var breathe_amplitude := float(indicator.get("breathe_amplitude"))
	var enter_duration := float(indicator.get("enter_duration"))
	var exit_duration := float(indicator.get("exit_duration"))

	indicator.call(&"play_enter", Vector3(2.0, 0.03, -3.0))
	_expect(
		indicator.visible and bool(indicator.call(&"is_effect_visible")),
		"play_enter makes the effect visible immediately"
	)
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_ENTER,
		"play_enter enters the ENTER state"
	)
	_expect(
		indicator.global_position.is_equal_approx(Vector3(2.0, 0.03, -3.0)),
		"play_enter places the effect at the requested world position"
	)
	_expect(
		float(indicator.call(&"get_presentation_alpha")) < maintain_opacity,
		"ENTER starts below the maintain opacity"
	)
	_expect(
		indicator.scale.x < 1.0,
		"ENTER starts smaller than the maintain scale"
	)

	await _wait_seconds(enter_duration + TIME_MARGIN)
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_MAINTAIN,
		"ENTER transitions to MAINTAIN after the enter duration"
	)
	_expect(
		is_equal_approx(indicator.scale.x, 1.0),
		"MAINTAIN restores the uniform scale to one"
	)
	_expect(
		absf(
			float(indicator.call(&"get_presentation_alpha")) - maintain_opacity
		) <= breathe_amplitude + 0.02,
		"MAINTAIN base opacity reaches the maintain value within breathing"
	)
	_expect(
		indicator.visible,
		"MAINTAIN keeps the effect visible"
	)

	indicator.call(&"update_world_position", Vector3(3.5, 0.03, -1.0))
	indicator.call(&"update_world_position", Vector3(-1.0, 0.03, 4.0))
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_MAINTAIN,
		"position updates do not replay the ENTER state"
	)
	_expect(
		indicator.global_position.is_equal_approx(Vector3(-1.0, 0.03, 4.0)),
		"the effect follows the latest world position"
	)

	var exit_position := indicator.global_position
	indicator.call(&"play_exit")
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_EXIT,
		"play_exit enters the EXIT state"
	)
	_expect(
		indicator.visible and bool(indicator.call(&"is_effect_visible")),
		"EXIT remains visible until the exit duration elapses"
	)
	await _wait_seconds(exit_duration + TIME_MARGIN)
	_expect(
		not indicator.visible and not bool(indicator.call(&"is_effect_visible")),
		"finished EXIT hides the effect"
	)
	_expect(
		indicator.global_position.is_equal_approx(exit_position),
		"EXIT keeps the last valid world position without touching the target"
	)

	indicator.call(&"play_enter", Vector3(0.5, 0.03, 0.5))
	await _wait_seconds(enter_duration + TIME_MARGIN)
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_MAINTAIN,
		"a fresh lock reaches MAINTAIN before interruption testing"
	)
	indicator.call(&"play_exit")
	await _wait_seconds(exit_duration * 0.4)
	indicator.call(&"play_enter", Vector3(-4.0, 0.03, 2.0))
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_ENTER,
		"a new lock interrupts the running EXIT immediately"
	)
	_expect(
		indicator.visible,
		"an interrupted EXIT becomes visible again"
	)
	_expect(
		indicator.global_position.is_equal_approx(Vector3(-4.0, 0.03, 2.0)),
		"the interrupted exit moves to the new target position"
	)
	await _wait_seconds(enter_duration + TIME_MARGIN)
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_MAINTAIN,
		"the interrupted exit settles into MAINTAIN normally"
	)

	indicator.call(&"hide_immediately")
	_expect(
		not indicator.visible and not bool(indicator.call(&"is_effect_visible")),
		"hide_immediately hides without playing the exit"
	)
	indicator.call(&"play_exit")
	_expect(
		not indicator.visible,
		"play_exit on a hidden effect stays a no-op"
	)
	indicator.call(&"hide_immediately")
	_expect(
		not indicator.visible,
		"repeated hide_immediately stays safe"
	)
	indicator.call(&"update_world_position", Vector3(7.0, 0.03, 7.0))
	_expect(
		not indicator.visible
		and not bool(indicator.call(&"is_effect_visible")),
		"updating the waiting position does not show the effect"
	)
	_expect(
		int(indicator.call(&"get_effect_state")) == STATE_EXIT,
		"updating the waiting position does not change the effect state"
	)
	_expect(
		indicator.global_position.is_equal_approx(Vector3(7.0, 0.03, 7.0)),
		"the waiting position is stored for later use"
	)

	indicator.queue_free()
	await process_frame
	_finish()


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("TargetLockIndicatorTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	print("TargetLockIndicatorTest: FAIL (%d)" % _failures.size())
	quit(1)
