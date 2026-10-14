extends Node3D
## 独立释放表现工具：不请求战斗技能，不改变正式配置；默认资产全部为空。
@export_category("Preview Assets")
## 仅工具使用的一次性视觉场景，默认空；正式技能应在自己的根节点配置。
@export var visual_scene: PackedScene
## 工具播放锚点，默认动作发射点；共用唯一技能枚举，不定义另一套规则。
@export var anchor: SkillBase.PresentationAnchor = SkillBase.PresentationAnchor.ACTION_ORIGIN
## 仅工具使用的一次性音频，默认空；不自动装备到正式技能。
@export var audio_stream: AudioStream
## 仅工具使用的镜头资源，默认空；只显示真实请求计数，不移动相机。
@export var camera_profile: CameraEffectProfile

@onready var _player: SkillReleasePresentationPlayer = $RuntimeEffects
@onready var _label: Label = $CanvasLayer/Panel/VBox/RequestCountLabel
@onready var _status: Label = $CanvasLayer/Panel/VBox/StatusLabel
var _request_count: int = 0

func _ready() -> void:
	$CanvasLayer/Panel/VBox/PlayButton.pressed.connect(play_preview)
	$CanvasLayer/Panel/VBox/TestChannelsButton.pressed.connect(_play_test_channels)
	_player.camera_effect_requested.connect(_on_camera_requested)
	_refresh_count()

## 根据工具根节点选定的资产播放一次；不验证费用/伤害，不发送虚假的技能成功信号。
func play_preview() -> void:
	_play(audio_stream, camera_profile)
	_status.text = "已播放所选资产；空通道会跳过。此工具不验证战斗结算。"

func _play_test_channels() -> void:
	_play(_test_tone(), CameraEffectProfile.new())
	_status.text = "测试音与镜头请求已发送（非正式内容）；相机保持不动。"

func _play(stream: AudioStream, profile: CameraEffectProfile) -> void:
	var context := SkillContext.new()
	context.caster = $SourceMarker
	context.resolved_target = $TargetMarker
	context.target_position = $TargetMarker.global_position
	context.delivery_parent = $WorldPlayback
	var action := Transform3D(Basis.IDENTITY, $SourceMarker.global_position + Vector3.UP)
	var snapshot := _player.prepare_release(context, action, visual_scene, anchor, stream, profile)
	_player.play_release(snapshot)

func _on_camera_requested(_profile: CameraEffectProfile, _source: Node3D,
		_target: Node3D, _world_transform: Transform3D) -> void:
	_request_count += 1
	_refresh_count()

func _refresh_count() -> void:
	_label.text = "镜头请求：%d（仅接口，无镜头移动）" % _request_count

# 内存工具测试音：0.15秒、440Hz、22050Hz单声道16bit；不保存成正式音频资产。
func _test_tone() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var count := int(22050 * 0.15)
	var data := PackedByteArray()
	data.resize(count * 2)
	for index in range(count):
		var envelope := sin(PI * float(index) / float(count))
		var sample := sin(TAU * 440.0 * float(index) / 22050.0) * envelope * 0.2
		data.encode_s16(index * 2, int(sample * 32767.0))
	stream.data = data
	return stream
