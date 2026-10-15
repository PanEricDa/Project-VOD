@tool
class_name ReleaseAccentProfile
extends Resource
## 仅描述释放强调，不持有运行状态。
## 成功释放后战场暂停秒数，默认0.15；0关闭，范围0—0.3；本次释放视觉/音频继续。
@export_range(0.0, 0.3, 0.01) var pause_duration_seconds: float = 0.15