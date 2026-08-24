extends CharacterBody3D

## EnemyBase 的基础物理脚本。
## 当前敌人只作为可检测靶子，因此只负责重力和稳定贴地，不包含移动、追击、生命值或攻击行为。

@export_category("Physics")
## 敌方单位受到的重力倍率。1.0 使用项目默认重力，0.0 可关闭重力。
@export_range(0.0, 10.0, 0.1, "or_greater") var gravity_multiplier: float = 1.0

## 从 Godot 项目设置中读取的默认三维重力加速度。
var gravity_force: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))


## 在固定物理帧中应用重力，并通过 move_and_slide 处理与地面的碰撞。
## 即使当前 Dummy 没有移动逻辑，也能够从空中落下并稳定停留在地面上。
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity_force * gravity_multiplier * delta
	else:
		velocity.y = -0.1

	move_and_slide()
