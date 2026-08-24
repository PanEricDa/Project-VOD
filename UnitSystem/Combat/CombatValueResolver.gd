class_name CombatValueResolver
extends RefCounted

## 统一计算伤害数值；来源为空时只使用基础伤害，防御仅由有效目标提供。
## damage_variance 为本次伤害的随机浮动比例，0 表示固定伤害；该值只应由武器普通攻击传入。
static func calculate_damage(
	source: UnitBase,
	target: UnitBase,
	base_damage: float,
	power_ratio: float = 1.0,
	multiplier: float = 1.0,
	damage_variance: float = 0.0
) -> float:
	var raw_damage: float = maxf(base_damage, 0.0) + _get_source_attack(source) * maxf(power_ratio, 0.0)
	var defense_multiplier: float = 1.0
	if is_instance_valid(target):
		defense_multiplier = 100.0 / (100.0 + target.get_defense())
	return raw_damage * defense_multiplier * maxf(multiplier, 0.0) * _roll_damage_variance(damage_variance)


## 对有效且存活的目标结算伤害，并返回生命值实际减少的数值。
## threat_multiplier 与 damage_variance 分别控制仇恨贡献和单次伤害浮动；两者都不影响技能的既有默认行为。
## 参数 threat_multiplier 会原样透传给目标的伤害入口，默认 1.0；它仅供 EnemyBase 在实际扣血后提交统一仇恨事件使用，绝不参与伤害公式。
static func apply_damage(
	source: UnitBase,
	target: UnitBase,
	base_damage: float,
	power_ratio: float = 1.0,
	multiplier: float = 1.0,
	threat_multiplier: float = 1.0,
	damage_variance: float = 0.0
) -> float:
	if not is_instance_valid(target) or target.is_dead():
		return 0.0
	return target.apply_damage(
		calculate_damage(source, target, base_damage, power_ratio, multiplier, damage_variance),
		source,
		threat_multiplier
	)


## 统一计算治疗数值；治疗不受目标防御影响，来源为空时只使用基础治疗量。
static func calculate_healing(
	source: UnitBase,
	base_amount: float,
	power_ratio: float = 0.0,
	multiplier: float = 1.0
) -> float:
	var raw_healing: float = maxf(base_amount, 0.0) + _get_source_attack(source) * maxf(power_ratio, 0.0)
	return raw_healing * maxf(multiplier, 0.0)


## 对有效且存活的目标结算治疗，并返回生命值实际恢复的数值。
static func apply_healing(
	source: UnitBase,
	target: UnitBase,
	base_amount: float,
	power_ratio: float = 0.0,
	multiplier: float = 1.0
) -> float:
	if not is_instance_valid(target) or target.is_dead():
		return 0.0
	return target.apply_healing(calculate_healing(source, base_amount, power_ratio, multiplier), source)


## 安全读取来源攻击力；空引用或已失效来源按零攻击力处理。
static func _get_source_attack(source: UnitBase) -> float:
	if not is_instance_valid(source):
		return 0.0
	return source.get_attack_power()


## 根据武器提供的比例为单次实际命中掷出伤害倍率。
## variance 为零时严格返回 1，确保未配置浮动的旧武器继续得到完全固定的伤害结果。
## 随机只在统一伤害结算入口调用一次，防止扣血、仇恨和界面显示分别取得不同结果。
static func _roll_damage_variance(variance: float) -> float:
	var normalized_variance: float = clampf(variance, 0.0, 1.0)
	if is_zero_approx(normalized_variance):
		return 1.0
	return randf_range(1.0 - normalized_variance, 1.0 + normalized_variance)
