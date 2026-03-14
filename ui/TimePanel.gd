extends Control

## 时间面板 UI 组件
## 负责显示当前游戏日期、时辰、旬进度及各类倒计时

# --- 常量 ---
const SHICHEN_NAMES = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
const MONTH_NAMES = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二"]
const XUN_NAMES = ["上旬", "中旬", "下旬"]
const DAY_NUMBERS = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

# --- 节点引用 (通过注释标注结构，方便美术替换) ---
# TimePanel (Control)
# ├── Background (NinePatchRect/TextureRect)
# └── MainLayout (VBoxContainer)
#     ├── MainTime (VBoxContainer)
#     │   ├── DateLabel (Label)
#     │   ├── ShichenLabel (Label)
#     │   └── DayProgress (ProgressBar)
#     ├── XunProgress (VBoxContainer)
#     │   ├── XunLabel (Label)
#     │   └── XunProgressRing (Control)
#     ├── Countdowns (VBoxContainer)
#     │   ├── PoetrySection (HBoxContainer)
#     │   ├── EnergySection (HBoxContainer)
#     │   └── RumorSection (HBoxContainer)
#     └── Doomsday (HBoxContainer)
#         ├── DeficitBar (ProgressBar)
#         └── FrictionBar (ProgressBar)

@onready var date_label: Label = $MainLayout/MainTime/DateLabel
@onready var shichen_label: Label = $MainLayout/MainTime/ShichenLabel
@onready var day_progress_bar: ProgressBar = $MainLayout/MainTime/DayProgress
@onready var xun_label: Label = $MainLayout/XunProgress/XunLabel
@onready var xun_progress_ring: Control = $MainLayout/XunProgress/XunProgressRing # 假设是一个自定义或带有进度显示的控件
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

func _input(event: InputEvent) -> void:
	# F12 快捷键切换时间面板显示
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_panel_visible = not _panel_visible
		visible = _panel_visible
		get_viewport().set_input_as_handled()

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

## 设置显示的区域 (e.g. ["poetry", "energy"])
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
	# 1. 时辰和当日进度
	var shichen_idx = int(GameTime.day_progress * 12) % 12
	shichen_label.text = SHICHEN_NAMES[shichen_idx] + "时"
	day_progress_bar.value = GameTime.day_progress * 100
	
	# 2. 旬进度
	var xun_day = (GameTime.current_day - 1) % 10 + 1
	xun_label.text = "本旬第 %d/10 日" % xun_day
	# 假设 xun_progress_ring 内部有更新逻辑，或者直接设置其属性
	if xun_progress_ring.has_method("set_value"):
		xun_progress_ring.set_value(GameTime.xun_progress * 100)
	
	# 3. 倒计时
	_update_countdowns()
	
	# 4. 数值闪烁 (内耗/亏空 > 80%)
	_update_warning_flashes()

func _update_date_display() -> void:
	var month_idx = (GameTime.current_month - 1) % 12
	var xun_idx = (GameTime.current_xun - 1) % 3
	var day_idx = (GameTime.current_day - 1) % 10
	
	var date_str = "「%s月%s第%s日」" % [
		MONTH_NAMES[month_idx], 
		XUN_NAMES[xun_idx], 
		DAY_NUMBERS[day_idx]
	]
	date_label.text = date_str

func _update_countdowns() -> void:
	# 诗社结算 (跟随旬结算)
	var time_to_xun = GameTime.time_to_next_xun
	_set_countdown_text(poetry_section, "诗社结算", time_to_xun)
	
	# 精力恢复 (2小时一次)
	var next_energy_sec = _get_next_energy_recovery_time()
	_set_countdown_text(energy_section, "精力恢复", next_energy_sec)
	
	# 流言到期 (如有)
	if _last_rumor_expiry > 0:
		var time_to_rumor = _last_rumor_expiry - Time.get_unix_time_from_system()
		if time_to_rumor > 0:
			_set_countdown_text(rumor_section, "流言到期", time_to_rumor)
			rumor_section.show()
		else:
			rumor_section.hide()
	else:
		rumor_section.hide()

func _set_countdown_text(container: HBoxContainer, label_prefix: String, seconds: float) -> void:
	var label = container.get_node("Label") as Label
	if not label: return
	
	var game_time_str = _format_game_time(seconds)
	var real_time_str = _format_real_time(seconds)
	label.text = "%s: %s %s" % [label_prefix, game_time_str, real_time_str]

func _format_game_time(seconds: float) -> String:
	# 换算规则：1 游戏日 = SECONDS_PER_DAY = 7200 现实秒
	# 1 时辰 = 1/12 游戏日 = 600 秒
	# 1 刻 = 1/8 时辰 = 75 秒
	var total_kes = int(seconds / 75.0)
	var shichen = total_kes / 8
	var kes = total_kes % 8
	return "%d时%d刻" % [shichen, kes]

func _format_real_time(seconds: float) -> String:
	var hours = seconds / 3600.0
	return "(约%.1f小时后)" % hours

func _get_next_energy_recovery_time() -> float:
	# 参考 PlayerState.get_current_stamina()
	var now = Time.get_unix_time_from_system()
	var last_refresh = PlayerState.last_stamina_refresh
	var recovery_sec = GameConfig.STAMINA_RECOVERY_SEC # 7200
	
	var elapsed = now - last_refresh
	var next_recovery_in = recovery_sec - fmod(elapsed, recovery_sec)
	return next_recovery_in

func _update_doomsday_bars() -> void:
	deficit_bar.value = GameState.deficit_value
	friction_bar.value = GameState.internal_conflict
	_update_doomsday_colors()

func _update_doomsday_colors() -> void:
	_set_bar_color(deficit_bar, GameState.deficit_value)
	_set_bar_color(friction_bar, GameState.internal_conflict)

func _set_bar_color(bar: ProgressBar, value: float) -> void:
	var style: StyleBoxFlat = bar.get_theme_stylebox("fill")
	if not style: return
	
	if value < 40:
		style.bg_color = Color.GREEN
	elif value < 60:
		style.bg_color = Color.YELLOW
	elif value < 80:
		style.bg_color = Color.ORANGE
	else:
		style.bg_color = Color.RED

func _update_warning_flashes() -> void:
	var t = Time.get_ticks_msec() / 500.0
	var flash = int(t) % 2 == 0
	
	if GameState.deficit_value >= 80:
		deficit_bar.modulate.a = 1.0 if flash else 0.3
	else:
		deficit_bar.modulate.a = 1.0
		
	if GameState.internal_conflict >= 80:
		friction_bar.modulate.a = 1.0 if flash else 0.3
	else:
		friction_bar.modulate.a = 1.0

# --- 信号回调 ---

func _on_day_changed(_new_day: int) -> void:
	_update_date_display()

func _on_xun_changed(_new_xun: int) -> void:
	_update_date_display()

func _on_deficit_changed(new_val: float) -> void:
	deficit_bar.value = new_val
	_update_doomsday_colors()

func _on_friction_changed(new_val: float) -> void:
	friction_bar.value = new_val
	_update_doomsday_colors()
