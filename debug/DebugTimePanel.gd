extends CanvasLayer

## 调试时间控制面板
## 仅在调试构建时有效，提供倍速、跳跃、数值修改及事件触发功能

@onready var panel: Panel = $Panel
@onready var speed_slider: HSlider = $Panel/VBox/TimeSection/SpeedHBox/SpeedSlider
@onready var speed_label: Label = $Panel/VBox/TimeSection/SpeedHBox/SpeedValueLabel
@onready var real_time_map_label: Label = $Panel/VBox/TimeSection/RealTimeMapLabel

@onready var deficit_slider: HSlider = $Panel/VBox/ValueSection/DeficitHBox/DeficitSlider
@onready var conflict_slider: HSlider = $Panel/VBox/ValueSection/ConflictHBox/ConflictSlider
@onready var stamina_slider: HSlider = $Panel/VBox/ValueSection/StaminaHBox/StaminaSlider
@onready var qi_shu_input: LineEdit = $Panel/VBox/ValueSection/QiShuHBox/QiShuInput

@onready var log_text: RichTextLabel = $Panel/VBox/LogSection/LogText

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _logs: Array[String] = []

func _ready() -> void:
	# 仅在调试模式下显示
	if not OS.is_debug_build():
		queue_free()
		return
		
	panel.hide() # 默认隐藏
	
	# 初始化倍速
	_on_speed_changed(GameTime.debug_speed_multiplier)
	
	# 连接信号
	GameTime.day_changed.connect(func(d): add_log("进入第 %d 日" % d, "日结算"))
	GameTime.xun_changed.connect(func(x): add_log("进入第 %d 旬" % x, "旬结算"))
	GameTime.month_changed.connect(func(m): add_log("进入第 %d 月" % m, "月结算"))
	
	# 初始化滑块数值
	deficit_slider.value = GameState.deficit_value
	conflict_slider.value = GameState.internal_conflict
	stamina_slider.value = PlayerState.stamina
	qi_shu_input.text = str(PlayerState.qi_shu)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_panel") or (event is InputEventKey and event.pressed and event.keycode == KEY_F12):
		panel.visible = !panel.visible
		if panel.visible:
			panel.grab_focus()

	if panel.visible:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed and panel.get_global_rect().has_point(event.global_position):
					_is_dragging = true
					_drag_offset = panel.global_position - event.global_position
				else:
					_is_dragging = false
		elif event is InputEventMouseMotion and _is_dragging:
			panel.global_position = event.global_position + _drag_offset

# --- A. 时间倍速控制 ---

func _on_speed_slider_changed(value: float) -> void:
	_on_speed_changed(value)

func _on_speed_btn_pressed(mult: float) -> void:
	speed_slider.value = mult
	_on_speed_changed(mult)

func _on_speed_changed(mult: float) -> void:
	GameTime.debug_speed_multiplier = mult
	speed_label.text = "%.1fx" % mult
	
	var game_min_per_real_min = mult
	var desc = ""
	if mult >= 3600:
		desc = "1现实分钟 ≈ %.1f游戏日" % (mult / 3600.0)
	elif mult >= 60:
		desc = "1现实分钟 ≈ %.1f游戏小时" % (mult / 60.0)
	else:
		desc = "1现实分钟 ≈ %.1f游戏分钟" % mult
		
	real_time_map_label.text = desc
	add_log("倍速调整为 %.1fx (%s)" % [mult, desc], "系统")

# --- B. 时间跳跃 ---

func jump_time(seconds: float) -> void:
	GameTime.debug_epoch_offset += seconds
	add_log("时间跳跃 %.1f 秒" % seconds, "跳跃")

func jump_to_day(day: int) -> void:
	var target_seconds = (day - 1) * GameTime.SECONDS_PER_DAY
	_set_absolute_game_time(target_seconds)
	add_log("跳转到第 %d 日" % day, "跳跃")

func jump_to_xun_settle_pre() -> void:
	# 跳到旬结算前5分钟 (现实时间)
	# 逻辑：当前旬的结束时间 - 5分钟现实时间对应的游戏时间
	var current_xun_end = GameTime.current_xun * GameTime.SECONDS_PER_XUN
	var pre_seconds = 300.0 * GameTime.debug_speed_multiplier
	_set_absolute_game_time(current_xun_end - pre_seconds)
	add_log("跳转到旬结算前5分钟", "跳跃")

func jump_to_month_settle_pre() -> void:
	var current_month_end = GameTime.current_month * GameTime.SECONDS_PER_MONTH
	var pre_seconds = 300.0 * GameTime.debug_speed_multiplier
	_set_absolute_game_time(current_month_end - pre_seconds)
	add_log("跳转到月结算前5分钟", "跳跃")

func jump_to_deficit_trigger() -> void:
	# 模拟内耗80%触发点
	GameState.internal_conflict = 80.0
	_sync_game_state_to_supabase({"conflict_value": 80.0})
	add_log("内耗设为 80% (即将触发抄检)", "触发")

func reset_all_debug_settings() -> void:
	GameTime.debug_speed_multiplier = 1.0
	GameTime.debug_epoch_offset = 0.0
	speed_slider.value = 1.0
	_on_speed_changed(1.0)
	add_log("重置所有调试设置", "系统")

func _set_absolute_game_time(target_game_seconds: float) -> void:
	var now = Time.get_unix_time_from_system()
	# game_seconds = (now - start + offset) * mult
	# offset = (game_seconds / mult) - (now - start)
	var mult = GameTime.debug_speed_multiplier if GameTime.debug_speed_multiplier > 0 else 1.0
	var start = GameTime._game_start_timestamp
	GameTime.debug_epoch_offset = (target_game_seconds / mult) - (now - start)

# --- C. 游戏数值快速设置 ---

func _on_deficit_slider_changed(value: float) -> void:
	GameState.deficit_value = value
	_sync_game_state_to_supabase({"deficit_value": value})
	add_log("亏空值调整: %.1f%%" % value, "数值")

func _on_conflict_slider_changed(value: float) -> void:
	GameState.internal_conflict = value
	_sync_game_state_to_supabase({"conflict_value": value})
	add_log("内耗值调整: %.1f%%" % value, "数值")

func _on_stamina_slider_changed(value: float) -> void:
	PlayerState.stamina = int(value)
	_sync_player_state_to_supabase({"stamina": int(value)})
	add_log("精力值调整: %d" % value, "数值")

func _on_qi_shu_submitted(text: String) -> void:
	var val = int(text)
	PlayerState.qi_shu = val
	_sync_player_state_to_supabase({"qi_points": val})
	add_log("气数调整: %d" % val, "数值")

func _sync_game_state_to_supabase(data: Dictionary) -> void:
	if GameState.current_game_id == "": return
	SupabaseManager.db_update("games", "id=eq." + GameState.current_game_id, data)

func _sync_player_state_to_supabase(data: Dictionary) -> void:
	if PlayerState.player_db_id == "": return
	SupabaseManager.db_update("players", "id=eq." + PlayerState.player_db_id, data)

# --- D. 事件强制触发 ---

func trigger_event(event_name: String) -> void:
	var confirm = ConfirmationDialog.new()
	confirm.dialog_text = "确定要强制触发「%s」吗？" % event_name
	confirm.confirmed.connect(func(): 
		GameState.special_event_triggered.emit(event_name)
		add_log("强制触发事件: %s" % event_name, "突发事件")
	)
	add_child(confirm)
	confirm.popup_centered()

# --- E. 日志窗口 ---

func add_log(content: String, category: String = "一般") -> void:
	var game_time_str = "D%d %02d:%02d" % [
		GameTime.current_day, 
		int(GameTime.day_progress * 24), 
		int(fmod(GameTime.day_progress * 24 * 60, 60))
	]
	var real_time_str = Time.get_time_string_from_system()
	var log_entry = "[%s] [%s] [%s] %s" % [game_time_str, real_time_str, category, content]
	
	_logs.push_front(log_entry)
	if _logs.size() > 20:
		_logs.pop_back()
		
	_update_log_display()

func _update_log_display() -> void:
	log_text.text = ""
	for l in _logs:
		log_text.text += l + "\n"

func export_logs() -> void:
	var full_text = ""
	for l in _logs:
		full_text += l + "\n"
	DisplayServer.clipboard_set(full_text)
	add_log("日志已复制到剪贴板", "系统")
