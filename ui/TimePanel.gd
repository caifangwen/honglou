extends Control

## 时间面板 UI 脚本
## 自动连接 GameTime 单例并更新显示

# 节点路径常量 (使用 @onready 替代以提高性能和稳定性)
@onready var main_time_label: Label = $PanelContainer/VBoxContainer/MainTime
@onready var shichen_label: Label = $PanelContainer/VBoxContainer/Shichen
@onready var day_progress_bar: ProgressBar = $PanelContainer/VBoxContainer/DayProgressBar
@onready var xun_day_label: Label = $PanelContainer/VBoxContainer/XunProgress/XunDayLabel
@onready var xun_countdown_label: Label = $PanelContainer/VBoxContainer/XunProgress/XunCountdownLabel
@onready var stamina_countdown_label: Label = $PanelContainer/VBoxContainer/Events/StaminaCountdown
@onready var rumor_countdown_label: Label = $PanelContainer/VBoxContainer/Events/RumorCountdown
@onready var deficit_bar: ProgressBar = $PanelContainer/VBoxContainer/DoomContainer/DeficitBar
@onready var conflict_bar: ProgressBar = $PanelContainer/VBoxContainer/DoomContainer/ConflictBar
@onready var events_container: VBoxContainer = $PanelContainer/VBoxContainer/Events
@onready var doom_container: HBoxContainer = $PanelContainer/VBoxContainer/DoomContainer
@onready var back_button: Button = $PanelContainer/VBoxContainer/BackButton

# 调试节点
@onready var debug_controls: VBoxContainer = $PanelContainer/VBoxContainer/DebugControls
@onready var speed_slider: HSlider = $PanelContainer/VBoxContainer/DebugControls/SpeedControl/SpeedSlider
@onready var speed_value_label: Label = $PanelContainer/VBoxContainer/DebugControls/SpeedControl/SpeedValue
@onready var day_jump_btn: Button = $PanelContainer/VBoxContainer/DebugControls/JumpGrid/DayJumpBtn
@onready var xun_jump_btn: Button = $PanelContainer/VBoxContainer/DebugControls/JumpGrid/XunJumpBtn
@onready var month_jump_btn: Button = $PanelContainer/VBoxContainer/DebugControls/JumpGrid/MonthJumpBtn
@onready var reset_debug_btn: Button = $PanelContainer/VBoxContainer/DebugControls/JumpGrid/ResetDebugBtn

# 属性
var visible_sections: Array[String] = ["main", "xun", "events", "doom"]
var last_refresh_time: float = 0.0 # 从 Supabase 读取的精力刷新时间
var current_stamina: int = 0
var max_stamina: int = 8

# 调试标记
var is_debug_mode: bool = false

func _ready() -> void:
	# 连接信号
	GameTime.day_changed.connect(_on_day_changed)
	GameTime.xun_changed.connect(_on_xun_changed)
	GameTime.month_changed.connect(_on_month_changed)
	
	if OS.is_debug_build():
		is_debug_mode = true
		GameTime.debug_speed_changed.connect(_on_debug_speed_changed)
		_setup_debug_controls()
	else:
		if debug_controls: debug_controls.hide()
	
	# 连接返回按钮
	if back_button:
		back_button.pressed.connect(_on_back_button_pressed)
	
	# 初始化显示
	_update_all_display()

func _process(_delta: float) -> void:
	_update_dynamic_elements()

## 控制显示哪些区域
func set_visible_sections(sections: Array[String]) -> void:
	visible_sections = sections
	if events_container: events_container.visible = sections.has("events")
	if doom_container: doom_container.visible = sections.has("doom")

func _update_all_display() -> void:
	# 检查节点是否已就绪
	if not is_inside_tree() or not main_time_label:
		return
		
	# 日期显示
	var month_name = TimeFormatter.CHINESE_NUMBERS[GameTime.current_month] if GameTime.current_month < 11 else str(GameTime.current_month)
	var xun_name = TimeFormatter.get_xun_name((GameTime.current_xun - 1) % 3)
	var day_name = TimeFormatter.CHINESE_NUMBERS[GameTime.current_day % 10] if GameTime.current_day % 10 != 0 else "十"
	
	main_time_label.text = "%s月%s第%s日" % [month_name, xun_name, day_name]
	
	# 旬进度
	var xun_day = (GameTime.current_day - 1) % 10 + 1
	xun_day_label.text = "%d/10" % xun_day

func _update_dynamic_elements() -> void:
	# 检查节点是否已就绪
	if not is_inside_tree() or not day_progress_bar:
		return

	# 当日进度
	day_progress_bar.value = GameTime.day_progress * 100
	
	# 时辰
	shichen_label.text = TimeFormatter.get_shichen(GameTime.day_progress) + "时"
	
	# 旬结算倒计时
	var xun_cd = TimeFormatter.to_countdown_string(GameTime.time_to_next_xun, GameTime.debug_speed_multiplier)
	xun_countdown_label.text = "距旬结算: " + xun_cd
	
	# 精力恢复倒计时
	if last_refresh_time > 0:
		var recovery = TimeFormatter.get_stamina_recovery_countdown(last_refresh_time, current_stamina, max_stamina, GameTime.debug_speed_multiplier)
		if recovery.next_recovery_in > 0:
			stamina_countdown_label.text = "精力恢复: " + TimeFormatter.to_countdown_string(recovery.next_recovery_in, GameTime.debug_speed_multiplier)
		else:
			stamina_countdown_label.text = "精力已满"

func _on_day_changed(_day: int) -> void:
	_update_all_display()

func _on_xun_changed(_xun: int) -> void:
	_update_all_display()

func _on_month_changed(_month: int) -> void:
	_update_all_display()

func _on_back_button_pressed() -> void:
	# 返回主界面 (假设 Hub.tscn 是主界面)
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

# --- 调试功能实现 ---

func _setup_debug_controls() -> void:
	if not debug_controls: return
	
	debug_controls.show()
	
	# 连接信号
	if speed_slider:
		speed_slider.value_changed.connect(_on_speed_slider_changed)
		# 同步当前倍速到滑块
		var multipliers = [1.0, 10.0, 60.0, 600.0, 3600.0]
		var current_idx = multipliers.find(GameTime.debug_speed_multiplier)
		if current_idx != -1:
			speed_slider.value = current_idx
			speed_value_label.text = "%gx" % GameTime.debug_speed_multiplier
	
	if day_jump_btn:
		day_jump_btn.pressed.connect(func(): _jump_time(GameTime.SECONDS_PER_DAY))
	if xun_jump_btn:
		xun_jump_btn.pressed.connect(func(): _jump_time(GameTime.SECONDS_PER_XUN))
	if month_jump_btn:
		month_jump_btn.pressed.connect(func(): _jump_time(GameTime.SECONDS_PER_MONTH))
	if reset_debug_btn:
		reset_debug_btn.pressed.connect(_on_reset_debug_pressed)

func _on_speed_slider_changed(val: float) -> void:
	var multipliers = [1.0, 10.0, 60.0, 600.0, 3600.0]
	var multiplier = multipliers[int(val)] if int(val) < multipliers.size() else val
	
	GameTime.debug_speed_multiplier = multiplier
	if speed_value_label:
		speed_value_label.text = "%gx" % multiplier
	
	_update_all_display()

func _jump_time(game_seconds: float) -> void:
	# 游戏秒数偏移转换为现实秒数偏移
	var real_offset = game_seconds / GameTime.debug_speed_multiplier
	GameTime.set_debug_epoch_offset(GameTime.debug_epoch_offset + real_offset)
	_update_all_display()

func _on_reset_debug_pressed() -> void:
	GameTime.debug_speed_multiplier = 1.0
	GameTime.debug_epoch_offset = 0.0
	if speed_slider: speed_slider.value = 0
	if speed_value_label: speed_value_label.text = "1x"
	_update_all_display()

func _on_debug_speed_changed(multiplier: float) -> void:
	# 同步 UI 组件
	if speed_slider:
		var multipliers = [1.0, 10.0, 60.0, 600.0, 3600.0]
		var idx = multipliers.find(multiplier)
		if idx != -1:
			speed_slider.set_value_no_signal(idx)
	if speed_value_label:
		speed_value_label.text = "%gx" % multiplier

	var label = get_node_or_null("DebugLabel")
	if not label:
		label = Label.new()
		label.name = "DebugLabel"
		add_child(label)
	
	if multiplier > 1.0:
		label.text = "⚡调试加速 x%d" % int(multiplier)
		label.modulate = Color.RED
	else:
		label.text = ""

## 外部接口：同步末日进度
func update_doom_values(deficit: float, conflict: float) -> void:
	if not deficit_bar or not conflict_bar: return
	
	deficit_bar.value = deficit
	conflict_bar.value = conflict
	
	# 颜色逻辑 (Green -> Red)
	deficit_bar.modulate = _get_doom_color(deficit)
	conflict_bar.modulate = _get_doom_color(conflict)
	
	# 闪烁逻辑
	if deficit > 80 or conflict > 80:
		_start_blink()

func _get_doom_color(val: float) -> Color:
	if val < 30: return Color.GREEN
	if val < 60: return Color.YELLOW
	if val < 80: return Color.ORANGE
	return Color.RED

func _start_blink() -> void:
	# 简单实现：使用 Tween 闪烁
	pass
