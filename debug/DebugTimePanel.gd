extends Control

## 调试时间控制面板
## 提供倍速控制、时间跳跃、数值设置及事件强制触发功能

signal debug_speed_changed(multiplier: float)

# 节点路径引用 (假设节点树结构)
@onready var log_window: RichTextLabel = get_node_or_null("VBoxContainer/LogWindow")
@onready var speed_slider: Slider = get_node_or_null("VBoxContainer/SpeedControl/Slider")
@onready var speed_display: Label = get_node_or_null("VBoxContainer/SpeedControl/Value")

func _ready() -> void:
	# 仅在调试构建中启用
	if not OS.is_debug_build():
		queue_free()
		return
		
	# 初始化倍速滑块
	if speed_slider:
		speed_slider.value_changed.connect(_on_speed_changed)
	
	_log("调试面板已就绪。按 F12 切换显示。")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_panel"):
		visible = !visible
		if visible:
			_log("面板已显示")

## 时间倍速控制
func _on_speed_changed(val: float) -> void:
	var multipliers = [1.0, 10.0, 60.0, 600.0, 3600.0]
	var multiplier = multipliers[int(val)] if int(val) < multipliers.size() else val
	
	GameTime.debug_speed_multiplier = multiplier
	if speed_display:
		speed_display.text = "当前速度: %gx (1现实分 ≈ %s游戏时间)" % [multiplier, _get_speed_desc(multiplier)]
	
	_log("速度调整为: %gx" % multiplier)
	debug_speed_changed.emit(multiplier)

func _get_speed_desc(multiplier: float) -> String:
	var game_minutes = multiplier # 1现实分钟 = multiplier 游戏分钟
	if game_minutes < 60:
		return "%d分" % int(game_minutes)
	elif game_minutes < 1440:
		return "%.1f小时" % (game_minutes / 60.0)
	else:
		return "%.1f日" % (game_minutes / 1440.0)

## 时间跳跃按钮点击处理
func jump_days(count: int) -> void:
	var game_seconds = count * GameTime.SECONDS_PER_DAY
	_apply_jump(game_seconds)

func jump_xuns(count: int) -> void:
	var game_seconds = count * GameTime.SECONDS_PER_XUN
	_apply_jump(game_seconds)

func jump_to_settlement(is_month: bool = false) -> void:
	var target_game_seconds = 0.0
	if is_month:
		# 跳到月结算前5分钟（游戏时间）
		target_game_seconds = (GameTime.current_month * GameTime.SECONDS_PER_MONTH) - 300.0
	else:
		# 跳到旬结算前5分钟
		target_game_seconds = (GameTime.current_xun * GameTime.SECONDS_PER_XUN) - 300.0
	
	# 计算当前游戏秒数
	var current_game_seconds = (Time.get_unix_time_from_system() - GameTime._game_start_timestamp + GameTime.debug_epoch_offset) * GameTime.debug_speed_multiplier
	_apply_jump(target_game_seconds - current_game_seconds)

func _apply_jump(game_seconds: float) -> void:
	# 游戏秒数偏移转换为现实秒数偏移
	var real_offset = game_seconds / GameTime.debug_speed_multiplier
	GameTime.set_debug_epoch_offset(GameTime.debug_epoch_offset + real_offset)
	_log("跳跃时间: %d 游戏秒" % int(game_seconds))

## 游戏数值设置
func set_deficit_value(val: float) -> void:
	# 实时写入 Supabase (模拟路径)
	if has_node("/root/SupabaseManager"):
		var sm = get_node("/root/SupabaseManager")
		sm.db_update("games", "id=eq." + GameTime._current_game_id, {"deficit_value": val})
	_log("亏空值设为: %.1f%%" % val)

func set_player_stamina(val: int) -> void:
	# 直接修改，绕过时间恢复
	if has_node("/root/SupabaseManager"):
		var sm = get_node("/root/SupabaseManager")
		sm.db_update("players", "id=eq." + sm.current_uid, {"current_stamina": val})
	_log("玩家精力设为: %d" % val)

## 事件强制触发
func trigger_event(event_name: String) -> void:
	# 这里通常通过 RPC 或 Edge Function 触发
	_log("强制触发事件: " + event_name)
	# 实际逻辑...

## 重置所有调试设置
func reset_all_debug_settings() -> void:
	GameTime.debug_speed_multiplier = 1.0
	GameTime.debug_epoch_offset = 0.0
	if speed_slider: speed_slider.value = 0
	_log("所有调试设置已重置")

func _log(msg: String) -> void:
	if not log_window: return
	var game_time_str = TimeFormatter.to_game_date_string(Time.get_unix_time_from_system(), GameTime._game_start_timestamp, GameTime.debug_speed_multiplier)
	var real_time_str = Time.get_time_string_from_system()
	log_window.append_text("[%s] [%s] %s\n" % [game_time_str, real_time_str, msg])
	# 自动滚动到底部
	var scroll = log_window.get_v_scroll_bar()
	scroll.value = scroll.max_value
