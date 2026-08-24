class_name FormationPositionData
extends Resource

## 友方单位可复用的阵型位置静态数据。
##
## 该资源只描述相对于当前跟随目标的编队中心和可游荡区域。它不保存单位实例、
## 随机目标、计时器或任何移动状态，因此同一份 .tres 可以被多个角色安全共享。

enum SideMode {
	FREE_CROSSING,
	LOCKED_RANDOM_SIDE,
	FIXED_LEFT,
	FIXED_RIGHT,
}

## 提供给 Inspector、未来阵型 UI 和调试界面的可读名称。
@export var display_name: String = "Formation Position"

@export_category("Center")
## 相对于跟随目标朝向的中心偏移。
## x 为右侧方向，负数表示左侧；y 为前方方向，负数表示后方。
@export var center_offset: Vector2 = Vector2(0.0, 2.5)

@export_category("Wander Area")
## 以阵型中心为基准，可向左右随机游荡的最大距离。
@export_range(0.0, 5.0, 0.05)
var lateral_radius: float = 1.1
## 使用锁侧模式时，目标点距离局部中心线的最小横向距离。
@export_range(0.0, 5.0, 0.05)
var lateral_minimum: float = 0.0
## 以阵型中心为基准，可向前后随机游荡的最大距离。
@export_range(0.0, 5.0, 0.05)
var forward_radius: float = 0.65
## 决定单位可自由跨越中心线，还是锁定在指定的一侧区域。
@export var side_mode: SideMode = SideMode.FREE_CROSSING
