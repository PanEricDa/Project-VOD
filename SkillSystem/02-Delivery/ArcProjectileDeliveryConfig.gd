@tool
class_name ArcProjectileDeliveryConfig
extends SkillDeliveryConfig

## 两参数弧线投射物的静态交付配置；飞行时长、弧高和命中规则仍由投射物场景决定。

## 发射时创建的投射物场景；默认空会拒绝交付。根节点须提供 launch(UnitBase, Vector3) -> bool 与 projectile_hit 信号，仅影响本技能的交付表现。
@export var projectile_scene: PackedScene


## 验证是否已指定投射物；实际脚本契约在实例化后由会话检查，避免无效场景发射。
func validate_configuration() -> PackedStringArray:
	if projectile_scene == null:
		return PackedStringArray(["Arc projectile delivery requires a projectile scene."])
	return PackedStringArray()
