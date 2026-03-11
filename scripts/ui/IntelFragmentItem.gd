extends Control

signal detail_pressed(fragment_id)
signal sell_pressed(fragment_id)
signal rumor_pressed(fragment_id)

@onready var type_icon = $HBox/TypeIcon
@onready var scene_label = $HBox/SceneLabel
@onready var value_stars = $HBox/ValueStars
@onready var time_label = $HBox/TimeLabel
@onready var detail_btn = $HBox/Actions/DetailBtn
@onready var sell_btn = $HBox/Actions/SellBtn
@onready var rumor_btn = $HBox/Actions/RumorBtn

var fragment_data: Dictionary

func setup(data: Dictionary):
	fragment_data = data
	
	# 设置类型图标 (此处使用文本模拟，实际应为 Texture)
	var type_name = data.get("intel_type", "unknown")
	_set_type_icon(type_name)
	
	# 设置来源场景
	scene_label.text = _localize_scene(data.get("scene", "unknown"))
	
	# 设置价值星级
	_set_value_stars(data.get("value_level", 1))
	
	# 更新倒计时
	_update_countdown()
	
	# 连接信号
	detail_btn.pressed.connect(func(): detail_pressed.emit(fragment_data["id"]))
	sell_btn.pressed.connect(func(): sell_pressed.emit(fragment_data["id"]))
	rumor_btn.pressed.connect(func(): rumor_pressed.emit(fragment_data["id"]))

func _process(_delta):
	_update_countdown()

func _update_countdown():
	var expires_at_str = fragment_data.get("expires_at", "")
	if expires_at_str == "": return
	
	# 简单清洗 ISO 8601 时间字符串以适配 Godot
	var clean_time = expires_at_str.split(".")[0].replace("T", " ").replace("Z", "")
	var expires_at = Time.get_unix_time_from_datetime_string(clean_time)
	var now = Time.get_unix_time_from_system()
	var diff = expires_at - now
	
	if diff <= 0:
		time_label.text = "已过期"
		time_label.add_theme_color_override("font_color", Color.GRAY)
		return
	
	var hours = int(diff / 3600)
	var minutes = int((int(diff) % 3600) / 60)
	var seconds = int(diff) % 60
	
	time_label.text = "%02d:%02d:%02d" % [hours, minutes, seconds]
	
	_check_expiry_warning(fragment_data)

func _check_expiry_warning(fragment: Dictionary):
	var expires_at_str = fragment.get("expires_at", "")
	if expires_at_str == "": return
	
	var expires_at = Time.get_unix_time_from_datetime_string(expires_at_str)
	var now = Time.get_unix_time_from_system()
	var diff = expires_at - now
	
	# 若剩余时间 < 2小时 (7200秒)，显示红色警告
	if diff > 0 and diff < 7200:
		time_label.add_theme_color_override("font_color", Color.RED)
	else:
		time_label.remove_theme_color_override("font_color")

func _set_type_icon(type: String):
	# 实际项目中应使用 Texture，这里模拟映射
	# account_leak / private_action / gift_record / visitor_info / elder_favor
	match type:
		"account_leak": type_icon.text = "[账]"
		"private_action": type_icon.text = "[动]"
		"gift_record": type_icon.text = "[礼]"
		"visitor_info": type_icon.text = "[访]"
		"elder_favor": type_icon.text = "[宠]"
		_: type_icon.text = "[?]"

func _localize_scene(scene: String) -> String:
	match scene:
		"yi_hong_yuan": return "怡红院"
		"treasury_back": return "后账房"
		"bridge": return "蜂腰桥"
		"gate": return "大门"
		"elder_room": return "贾母处"
		_: return scene

func _set_value_stars(level: int):
	var stars = ""
	for i in range(5):
		stars += "★" if i < level else "☆"
	value_stars.text = stars
