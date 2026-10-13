@tool
class_name ArcProjectileDeliveryConfig
extends SkillDeliveryConfig

## 两参数弧线投射物的静态交付配置；飞行时长、弧高和命中规则仍由投射物场景决定。

## 发射时创建的投射物场景；默认空会拒绝交付。根节点须提供 launch(UnitBase, Vector3) -> bool 与 projectile_hit 信号，仅影响本技能的交付表现。
@export var projectile_scene: PackedScene
## 释放前扩展 Arc 投射物目标的策略；默认空表示只攻击已解析主要目标，
## 不改变现有连射语义。配置后每个目标各发 shot_count 枚，作用于本次交付。
@export var target_expansion: SkillTargetExpansion
## 每个入选目标发出的投射物数量；默认 1 保持普通单箭行为，
## 无目标扩展时等于本次释放的总发射数，只影响本次弧线交付。
@export_range(1, 32, 1) var shot_count: int = 1
## 整轮目标序列中相邻两次发射的间隔，单位秒；默认 0 表示同帧齐射，
## 只影响本次弧线交付，不修改技能施法时间。
@export_range(0.0, 5.0, 0.01, "or_greater") var shot_interval_seconds: float = 0.0


## 验证是否已指定投射物；实际脚本契约在实例化后由会话检查，避免无效场景发射。
func validate_configuration() -> PackedStringArray:
	var warnings := PackedStringArray()
	if projectile_scene == null:
		warnings.append("Arc projectile delivery requires a projectile scene.")
	if shot_count < 1 or shot_count > 32:
		warnings.append("Arc projectile shot count must be between 1 and 32.")
	if not is_finite(shot_interval_seconds) or shot_interval_seconds < 0.0:
		warnings.append("Arc projectile shot interval must be finite and nonnegative.")
	return warnings
