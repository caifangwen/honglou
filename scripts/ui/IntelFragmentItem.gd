extends Control

# IntelFragmentItem.gd - 情报碎片列表项
# 展示单条情报的核心信息，提供查看详情、出售、发布流言等操作

signal detail_pressed(fragment_id)
signal sell_pressed(fragment_id)
signal rumor_pressed(fragment_id)
signal expired(fragment_id)

@onready var type_icon = $HBox/TypeIcon
@onready var scene_label = $HBox/SceneLabel
@onready var value_stars = $HBox/ValueStars
@onready var time_label = $HBox/TimeLabel
@onready var detail_btn = $HBox/Actions/DetailBtn
@onready var sell_btn = $HBox/Actions/SellBtn
@onready var rumor_btn = $HBox/Actions/RumorBtn

var fragment_data: Dictionary
var _is_expired: bool = false
var _update_interval: float = 1.0 # 倒计时更新间隔（秒）
var _update_timer: float = 0.0

func _ready():
	# 初始设置
	if fragment_data.is_empty():
		return
	
	_setup_ui()

func setup(data: Dictionary):
	fragment_data = data
	_setup_ui()

func _setup_ui():
	# 设置类型图标
	var type_name = fragment_data.get("intel_type", "unknown")
	_set_type_icon(type_name)

	# 设置来源场景
	var scene = fragment_data.get("scene_key", fragment_data.get("scene", "unknown"))
	scene_label.text = _localize_scene(scene)

	# 设置价值星级
	_set_value_stars(fragment_data.get("value_level", 1))

	# 连接信号
	detail_btn.pressed.connect(func(): detail_pressed.emit(fragment_data["id"]))
	sell_btn.pressed.connect(func(): sell_pressed.emit(fragment_data["id"]))
	rumor_btn.pressed.connect(func(): rumor_pressed.emit(fragment_data["id"]))
	
	# 初始更新倒计时
	_update_countdown()

func _process(delta):
	if _is_expired:
		return
	
	_update_timer += delta
	if _update_timer >= _update_interval:
		_update_timer = 0.0
		_update_countdown()

func _update_countdown():
	var expires_at_str = fragment_data.get("expires_at", "")
	if expires_at_str == "":
		return

	# 解析过期时间
	var clean_time = _clean_iso_time(expires_at_str)
	var expires_at = Time.get_unix_time_from_datetime_string(clean_time)
	var now = Time.get_unix_time_from_system()
	var diff = expires_at - now

	if diff <= 0:
		_on_expired()
		return

	# 格式化倒计时
	var time_text = _format_time(diff)
	time_label.text = time_text
	
	# 根据剩余时间设置颜色
	_set_time_color(diff)

func _clean_iso_time(iso_time: String) -> String:
	# 清洗 ISO 8601 时间字符串以适配 Godot
	return iso_time.split(".")[0].replace("T", " ").replace("Z", "")

func _format_time(diff: float) -> String:
	var hours = int(diff / 3600)
	var minutes = int((int(diff) % 3600) / 60)
	var seconds = int(diff) % 60
	
	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, seconds]
	else:
		# 小于 1 小时时显示分秒
		return "%02d:%02d" % [minutes, seconds]

func _set_time_color(diff: float):
	# 剩余时间 < 2 小时，显示红色警告
	if diff < 7200:
		time_label.add_theme_color_override("font_color", Color.RED)
	# 剩余时间 < 6 小时，显示橙色警告
	elif diff < 21600:
		time_label.add_theme_color_override("font_color", Color.ORANGE)
	else:
		time_label.remove_theme_color_override("font_color")

func _on_expired():
	_is_expired = true
	time_label.text = "已过期"
	time_label.add_theme_color_override("font_color", Color.GRAY)
	
	# 禁用按钮
	detail_btn.disabled = true
	sell_btn.disabled = true
	rumor_btn.disabled = true
	
	# 发出过期信号
	expired.emit(fragment_data["id"])

func _set_type_icon(type: String):
	match type:
		"account_leak":
			type_icon.text = "[账]"
			type_icon.tooltip_text = "账目泄露"
		"private_action":
			type_icon.text = "[行]"
			type_icon.tooltip_text = "私密行动"
		"gift_record":
			type_icon.text = "[礼]"
			type_icon.tooltip_text = "馈赠记录"
		"visitor_info":
			type_icon.text = "[访]"
			type_icon.tooltip_text = "访客信息"
		"elder_favor":
			type_icon.text = "[宠]"
			type_icon.tooltip_text = "长辈青睐"
		_:
			type_icon.text = "[?]"
			type_icon.tooltip_text = "未知类型"

func _localize_scene(scene: String) -> String:
	match scene:
		"yi_hong_yuan":
			return "怡红院"
		"treasury_back":
			return "后账房"
		"treasury_room":
			return "后账房"
		"bridge":
			return "蜂腰桥"
		"gate":
			return "大门"
		"elder_room":
			return "贾母处"
		_:
			return scene

func _set_value_stars(level: int):
	level = clamp(level, 1, 5)
	var stars = ""
	for i in range(5):
		stars += "★" if i < level else "☆"
	value_stars.text = stars
	
	# 根据价值设置颜色
	if level >= 5:
		value_stars.add_theme_color_override("font_color", Color(1, 0.84, 0, 1)) # 金色
	elif level >= 4:
		value_stars.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 1)) # 蓝色
	elif level >= 3:
		value_stars.remove_theme_color_override("font_color") # 白色
	else:
		value_stars.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1)) # 灰色
