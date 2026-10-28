extends SkillEffectBase

## 仅用于PlayerSkills测试目录；真实Delivery调用apply后上报，不造成伤害、位移、仇恨或费用。
## context为本次正式交付快照，target为实际Effect目标；事件不授权订阅者再次执行交付。
signal applied(context: SkillContext, target: Node3D)

## 沿用通用Effect签名，result由Delivery提供；仅接受存活的context施法者自身作为探针目标。
func apply(context: SkillContext, _result: SkillDeliveryResult, target: Node3D) -> bool:
	if context == null or not is_instance_valid(target) or target != context.caster:
		return false
	applied.emit(context, target)
	return true
