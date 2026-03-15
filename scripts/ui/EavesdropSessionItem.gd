extends PanelContainer

# EavesdropSessionItem.gd - 挂机会话列表项

signal cancel_pressed(session_id: String)

@onready var scene_label = $HBoxContainer/SceneLabel
@onready var time_label = $HBoxContainer/TimeLabel
@onready var status_label = $HBoxContainer/StatusLabel
@onready var intel_count_label = $HBoxContainer/IntelCountLabel
@onready var cancel_btn = $HBoxContainer/CancelBtn

var session_data: Dictionary
var _remaining_seconds: int = 0

func _ready():
	if not session_data.is_empty():
		setup(session_data)

func setup(data: Dictionary):
	session_data = data
	
	var scene_key = data.get("scene_key", "unknown")
	var scene_name = EavesdropManager.SCENE_CONFIGS.get(scene_key, {}).get("name", scene_key)
	scene_label.text = scene_name
	
	# 状态
	var status = data.get("status", "active")
	status_label.text = _localize_status(status)
	
	# 情报数量
	intel_count_label.text = "已获情报：%d" % data.get("result_count", 0)
	
	# 取消按钮
	cancel_btn.pressed.connect(func(): cancel_pressed.emit(data["id"]))
	
	# 初始更新计时器
	update_timer()

func update_timer():
	var ends_at_str = session_data.get("ends_at", "")
	if ends_at_str == "":
		return
	
	var clean_time = ends_at_str.split(".")[0].replace("T", " ").replace("Z", "")
	var ends_at = Time.get_unix_time_from_datetime_string(clean_time)
	var now = Time.get_unix_time_from_system()
	_remaining_seconds = max(0, int(ends_at - now))
	
	time_label.text = _format_remaining_time(_remaining_seconds)
	
	# 检查是否完成
	if _remaining_seconds <= 0:
		status_label.text = "已完成"
		status_label.add_theme_color_override("font_color", Color.LIME_GREEN)
		cancel_btn.disabled = true
		cancel_btn.text = "已完成"

func _format_remaining_time(seconds: int) -> String:
	if seconds <= 0:
		return "已完成"
	
	var hours = seconds / 3600
	var minutes = (seconds % 3600) / 60
	var secs = seconds % 60
	
	if hours > 0:
		return "%d 小时 %d 分" % [hours, minutes]
	else:
		return "%d 分 %d 秒" % [minutes, secs]

func _localize_status(status: String) -> String:
	match status:
		"active": return "进行中"
		"completed": return "已完成"
		"cancelled": return "已取消"
		_: return status
