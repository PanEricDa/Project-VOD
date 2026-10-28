extends "res://Effects/Skills/FlameBarrage/FlameBarrageEffectPlayer.gd"
## 通用范围释放视觉：VisualRoot/RangeRoot下以1米为最大半径制作扩散动画。
## 继承既有播放、时钟、回收逻辑；中央圣徽等放在RangeRoot外，不随范围变大。

## radius_m为本次技能的实际水平作用半径（米），由释放播放器在入树前注入。
## 只设置本实例RangeRoot的XZ尺寸；重复调用不累乘，非有限或非正值忽略。
func configure_effect_radius(radius_m: float) -> void:
	if not is_finite(radius_m) or radius_m <= 0.0: return
	var range_root := get_node_or_null("VisualRoot/RangeRoot") as Node3D
	if range_root != null:
		range_root.scale = Vector3(radius_m,1.0,radius_m)
