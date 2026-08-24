extends SceneTree

## 单场景技能系统基础契约测试。
##
## 此测试只验证无场景树依赖的运行时数据、交付配置和扩展组件基类，
## 确保后续 SkillBase、SkillHost 与 UnitSystem 只依赖稳定、强类型的公开接口。

const ROOT_PATH := "res://SkillSystem/"

var _failures: Array[String] = []


func _initialize() -> void:
	_verify_script_contracts()
	call_deferred(&"_finish")


func _verify_script_contracts() -> void:
	var required_scripts: Array[String] = [
		ROOT_PATH + "01-Core/SkillContext.gd",
		ROOT_PATH + "01-Core/SkillDeliveryResult.gd",
		ROOT_PATH + "02-Delivery/SkillDeliveryConfig.gd",
		ROOT_PATH + "02-Delivery/TrackingProjectileDeliveryConfig.gd",
		ROOT_PATH + "02-Delivery/InstantTargetDeliveryConfig.gd",
		ROOT_PATH + "02-Delivery/GroundAreaDeliveryConfig.gd",
		ROOT_PATH + "03-Extensions/SkillConditionBase.gd",
		ROOT_PATH + "03-Extensions/SkillCostBase.gd",
		ROOT_PATH + "03-Extensions/SkillEffectBase.gd",
	]
	for script_path: String in required_scripts:
		_expect(ResourceLoader.exists(script_path), "Missing script: " + script_path)
		if ResourceLoader.exists(script_path):
			var required_script := load(script_path) as Script
			_expect(
				required_script != null and required_script.can_instantiate(),
				"Script must compile and instantiate: " + script_path
			)
			if "02-Delivery/" in script_path:
				_expect(
					required_script != null and required_script.is_tool(),
					(
						"Delivery Resource scripts used by SkillBase editor "
						+ "validation must run in tool mode: "
						+ script_path
					)
				)

	if not ResourceLoader.exists(
		ROOT_PATH + "02-Delivery/TrackingProjectileDeliveryConfig.gd"
	):
		return

	var tracking_script := load(
		ROOT_PATH + "02-Delivery/TrackingProjectileDeliveryConfig.gd"
	) as Script
	var tracking: Resource = tracking_script.new()
	_expect(tracking.get("projectile_scene") == null, "Projectile scene defaults to null")
	_expect(
		is_equal_approx(float(tracking.get("projectile_speed")), 12.0),
		"Projectile speed defaults to 12 m/s"
	)
	_expect(
		(tracking.call("validate_configuration") as PackedStringArray).size() == 1,
		"Tracking config reports exactly one missing-projectile warning"
	)

	var instant_script := load(
		ROOT_PATH + "02-Delivery/InstantTargetDeliveryConfig.gd"
	) as Script
	var instant: Resource = instant_script.new()
	_expect(
		(instant.call("validate_configuration") as PackedStringArray).is_empty(),
		"Instant target config is valid without dummy fields"
	)

	var ground_script := load(
		ROOT_PATH + "02-Delivery/GroundAreaDeliveryConfig.gd"
	) as Script
	var ground: Resource = ground_script.new()
	_expect(
		(ground.call("validate_configuration") as PackedStringArray).size() == 1,
		"Ground-area config requires an area scene"
	)

	var context_script := load(ROOT_PATH + "01-Core/SkillContext.gd") as Script
	if context_script == null or not context_script.can_instantiate():
		return
	var context: RefCounted = context_script.new()
	var candidate := Node3D.new()
	var candidates: Array[Node3D] = [candidate]
	context.set("candidate_targets", candidates)
	context.set("target_position", Vector3(3.0, 0.0, 4.0))
	var copy: RefCounted = context.call("duplicate_context") as RefCounted
	var copied_candidates: Array = copy.get("candidate_targets") as Array
	_expect(copied_candidates.size() == 1, "Context copies candidate targets")
	_expect(
		copy.get("target_position") == Vector3(3.0, 0.0, 4.0),
		"Context copies the target position"
	)
	## 延迟施法期间目标可能已死亡并释放；复制上下文必须安全清空失效引用。
	context.set("requested_target", candidate)
	context.set("resolved_target", candidate)
	candidate.free()
	var released_target_copy: RefCounted = context.call("duplicate_context") as RefCounted
	_expect(
		released_target_copy != null,
		"Context duplication survives a previously freed target"
	)
	_expect(
		released_target_copy != null and released_target_copy.get("requested_target") == null,
		"Context clears a previously freed requested target"
	)
	_expect(
		released_target_copy != null and released_target_copy.get("resolved_target") == null,
		"Context clears a previously freed resolved target"
	)
	_expect(
		released_target_copy != null and (released_target_copy.get("candidate_targets") as Array).is_empty(),
		"Context removes previously freed candidate targets"
	)

	var condition_script := load(
		ROOT_PATH + "03-Extensions/SkillConditionBase.gd"
	) as Script
	var condition: Node = condition_script.new()
	_expect(
		not bool(condition.call("evaluate", context)),
		"Base condition fails closed"
	)
	condition.free()

	var cost_script := load(
		ROOT_PATH + "03-Extensions/SkillCostBase.gd"
	) as Script
	var cost: Node = cost_script.new()
	_expect(not bool(cost.call("can_pay", context)), "Base cost fails closed")
	_expect(not bool(cost.call("commit", context)), "Base cost cannot commit")
	cost.call("refund", context)
	cost.call("refund", context)
	cost.free()

	var effect_script := load(
		ROOT_PATH + "03-Extensions/SkillEffectBase.gd"
	) as Script
	var effect: Node = effect_script.new()
	_expect(
		not bool(effect.call("apply", context, null, null)),
		"Base effect fails closed"
	)
	effect.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("SingleSceneCoreContractsTest: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)
