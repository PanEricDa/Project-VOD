extends Node3D

## 溶解开始时可选叠加的金白色余烬效果。
## 本效果不参与单位销毁计时，独立完成表现并自行回收。

@export_range(0.05, 5.0, 0.05, "or_greater") var lifetime: float = 0.8


func _ready() -> void:
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
