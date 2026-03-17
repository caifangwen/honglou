extends Control

## 时间面板 UI 组件
## 负责显示当前游戏日期、时辰、旬进度及各类倒计时

# --- 常量 ---
const SHICHEN_NAMES = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
const MONTH_NAMES = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二"]
const XUN_NAMES = ["上旬", "中旬", "下旬"]
const DAY_NUMBERS = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

# --- 节点引用 ---
@onready var date_label: Label = $MainLayout/MainTime/DateLabel
@onready var shichen_label: Label = $MainLayout/MainTime/ShichenLabel
@onready var day_progress_bar: ProgressBar = $MainLayout/MainTime/DayProgress
@onready var xun_label: Label = $MainLayout/XunProgress/XunLabel
@onready var xun_progress_ring: Control = $MainLayout/XunProgress/XunProgressRing
@onready var countdowns_container: VBoxContainer = $MainLayout/Countdowns
@onready var poetry_section: HBoxContainer = $MainLayout/Countdowns/PoetrySection
@onready var energy_section: HBoxContainer = $MainLayout/Countdowns/EnergySection
@onready var rumor_section: HBoxContainer = $MainLayout/Countdowns/RumorSection
@onready var deficit_bar: ProgressBar = $MainLayout/Doomsday/DeficitBar
@onready var friction_bar: ProgressBar = $MainLayout/Doomsday/FrictionBar

# --- 状态变量 ---
var _visible_sections: Array[String] = ["poetry", "energy", "rumor"]
var _last_rumor_expiry: float = -1.0
var _panel_visible: bool = true

func _ready() -> void:
	# 连接信号
	GameTime.day_changed.connect(_on_day_changed)
	GameTime.xun_changed.connect(_on_xun_changed)
	GameState.deficit_changed.connect(_on_deficit_changed)
	GameState.conflict_changed.connect(_on_friction_changed)

	# 初始化显示
	_update_all()
	_update_doomsday_colors()

func _process(_delta: float) -> void:
	_update_realtime_displays()

# --- 公开方法 ---

func set_visible_sections(sections: Array[String]) -> void:
	_visible_sections = sections
	poetry_section.visible = "poetry" in sections
	energy_section.visible = "energy" in sections
	rumor_section.visible = "rumor" in sections

# --- 内部逻辑 ---

func _update_all() -> void:
	_update_date_display()
	_update_doomsday_bars()

func _update_realtime_displays() -> void:
	var shichen_idx = int(GameTime.day_progress * 12) % 12
	shichen_label.text = SHICHEN_NAMES[shichen_idx] + "时"
	day_progress_bar.value = GameTime.day_progress * 100

	var xun_day = (GameTime.current_day - 1) % 10 + 1
	xun_label.text = "本旬第 %d/10 日" % xun_day
	if xun_progress_ring.has_method("set_value"):
		xun_progress_ring.set_value(GameTime.xun_progress * 100)

	_update_countdowns()
	_update_warning_flashes()

func _update_date_display() -> void:
	var month_idx = (GameTime.current_month - 1) % 12
	var xun_idx = (GameTime.current_xun - 1) % 3
	var day_idx = (GameTime.current_day - 1) % 10
	date_label.text = "红楼 %s月 %s旬 第%s日" % [MONTH_NAMES[month_idx], XUN_NAMES[xun_idx], DAY_NUMBERS[day_idx]]

func _update_countdowns() -> void:
	# 诗社倒计时
	if poetry_section.get_child_count() > 1:
		var time_to_poetry = GameTime.time_to_next_xun
		poetry_section.get_child(1).text = "诗社：%d 秒" % int(time_to_poetry)

	# 精力恢复倒计时
	if energy_section.get_child_count() > 1:
		var time_to_stamina = GameTime.time_to_next_day
		energy_section.get_child(1).text = "精力恢复：%d 秒" % int(time_to_stamina)

	# 流言到期倒计时
	if rumor_section.get_child_count() > 1:
		var time_to_rumor = _last_rumor_expiry - Time.get_unix_time_from_system()
		if time_to_rumor > 0:
			rumor_section.get_child(1).text = "流言到期：%d 秒" % int(time_to_rumor)
		else:
			rumor_section.get_child(1).text = "流言已到期"

func _update_warning_flashes() -> void:
	var deficit_flash = deficit_bar.value >= 80.0
	var friction_flash = friction_bar.value >= 80.0
	deficit_bar.modulate.a = 1.0 if deficit_flash else 0.5
	friction_bar.modulate.a = 1.0 if friction_flash else 0.5

func _update_doomsday_bars() -> void:
	deficit_bar.value = GameState.deficit_value
	friction_bar.value = GameState.internal_conflict
	_update_doomsday_colors()

func _update_doomsday_colors() -> void:
	var deficit_style = StyleBoxFlat.new()
	deficit_style.bg_color = Color(0.1, 0.6, 0.1, 1.0) if GameState.deficit_value < 80.0 else Color(0.8, 0.1, 0.1, 1.0)
	deficit_bar.add_theme_stylebox_override("fill", deficit_style)

	var friction_style = StyleBoxFlat.new()
	friction_style.bg_color = Color(0.1, 0.6, 0.1, 1.0) if GameState.internal_conflict < 80.0 else Color(0.8, 0.1, 0.1, 1.0)
	friction_bar.add_theme_stylebox_override("fill", friction_style)

# --- 信号回调 ---

func _on_day_changed(new_day: int) -> void:
	_update_all()
	print("[TimePanel] 进入第 %d 日" % new_day)

func _on_xun_changed(new_xun: int) -> void:
	_update_all()
	print("[TimePanel] 进入第 %d 旬" % new_xun)

func _on_deficit_changed(new_value: float) -> void:
	deficit_bar.value = new_value
	_update_doomsday_colors()

func _on_friction_changed(new_value: float) -> void:
	friction_bar.value = new_value
	_update_doomsday_colors()
