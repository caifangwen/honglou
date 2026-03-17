extends Control

# EavesdropHub.gd - 挂机监听中心
# 显示所有活跃会话、剩余时间、收益统计，支持取消会话

signal back_pressed()

@onready var active_sessions_container = $MainContainer/SessionsPanel/ActiveSessionsContainer
@onready var stats_label = $MainContainer/StatsLabel
@onready var back_btn = $TopBar/BackButton
@onready var refresh_btn = $MainContainer/ButtonPanel/RefreshBtn
@onready var new_session_btn = $MainContainer/ButtonPanel/NewSessionBtn

@onready var cancel_confirm_dialog = $CancelConfirmDialog

const SESSION_ITEM_SCENE = preload("res://features/eavesdrop/EavesdropSessionItem.tscn")

var _active_sessions: Array = []
var _refresh_timer: Timer
var _debug_timer: Timer

func _ready():
	print("[EavesdropHub] _ready called")
	_setup_ui()
	_setup_timers()
	_setup_debug_timer()
	await _load_active_sessions()

func _setup_ui():
	print("[EavesdropHub] _setup_ui called")
	print("[EavesdropHub] back_btn valid: ", is_instance_valid(back_btn))
	print("[EavesdropHub] refresh_btn valid: ", is_instance_valid(refresh_btn))
	print("[EavesdropHub] new_session_btn valid: ", is_instance_valid(new_session_btn))
	
	if is_instance_valid(back_btn):
		back_btn.pressed.connect(_on_back_pressed)
	if is_instance_valid(refresh_btn):
		refresh_btn.pressed.connect(_on_refresh_pressed)
	if is_instance_valid(new_session_btn):
		new_session_btn.pressed.connect(_on_new_session_pressed)

func _setup_timers():
	# 每 5 秒刷新一次倒计时
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 5.0
	_refresh_timer.timeout.connect(_update_session_timers)
	_refresh_timer.autostart = true
	add_child(_refresh_timer)

func _setup_debug_timer():
	# 创建调试定时器，每 10 秒打印一次精力状态
	_debug_timer = Timer.new()
	_debug_timer.wait_time = 10.0
	_debug_timer.timeout.connect(_print_stamina_debug_info)
	_debug_timer.autostart = true
	add_child(_debug_timer)
	print("[EavesdropHub] 精力调试定时器已启动")

func _print_stamina_debug_info():
	var current = PlayerState.get_current_stamina()
	var max_val = PlayerState.stamina_max
	var elapsed = int(Time.get_unix_time_from_system()) - PlayerState.last_stamina_refresh
	print("[EavesdropHub] 【精力调试】当前：%d/%d, 最后刷新：%d 秒前，自动恢复：%.1f 小时后" % [
		current, max_val, elapsed, (GameConfig.STAMINA_RECOVERY_SEC - elapsed) / 3600.0
	])

func _load_active_sessions():
	print("[EavesdropHub] _load_active_sessions called")
	
	# 检查节点是否有效
	if not is_instance_valid(active_sessions_container):
		print("[EavesdropHub] active_sessions_container is invalid!")
		return
	
	# 清空现有项
	for child in active_sessions_container.get_children():
		child.queue_free()

	_active_sessions.clear()

	# 加载活跃会话
	var sessions = await EavesdropManager.get_active_sessions()
	print("[EavesdropHub] get_active_sessions returned: ", sessions)
	
	if sessions is Array:
		_active_sessions = sessions
	else:
		print("[EavesdropHub] get_active_sessions returned non-Array: ", typeof(sessions))
		_active_sessions = []

	# 更新统计
	_update_stats()

	if _active_sessions.is_empty():
		print("[EavesdropHub] No active sessions, showing hint")
		_show_no_sessions_hint()
		return

	print("[EavesdropHub] Creating ", _active_sessions.size(), " session items")
	
	# 创建会话项
	for session in _active_sessions:
		var item = SESSION_ITEM_SCENE.instantiate()
		active_sessions_container.add_child(item)
		item.setup(session)
		item.cancel_pressed.connect(_on_cancel_session_pressed)

func _show_no_sessions_hint():
	var label = Label.new()
	label.text = "当前没有活跃的挂机会话\n点击「新建挂机」开始监听"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	active_sessions_container.add_child(label)

func _update_stats():
	var total = _active_sessions.size()
	var completed_today = 0 # 可以从历史记录统计
	var total_intel = 0
	
	for session in _active_sessions:
		total_intel += session.get("result_count", 0)
	
	stats_label.text = "活跃会话：%d | 已获情报：%d" % [total, total_intel]

func _update_session_timers():
	for child in active_sessions_container.get_children():
		if child.has_method("update_timer"):
			child.update_timer()

func _on_cancel_session_pressed(session_id: String):
	print("[EavesdropHub] _on_cancel_session_pressed: ", session_id)
	cancel_confirm_dialog.dialog_text = "确定要取消此挂机会话吗？\n已消耗的精力不会退还。"
	cancel_confirm_dialog.popup_centered()
	
	# 存储要取消的会话 ID
	var cancel_data = {"session_id": session_id}
	
	# 连接 confirmed 信号（一次性）
	cancel_confirm_dialog.confirmed.connect(_on_cancel_confirmed.bind(cancel_data), CONNECT_ONE_SHOT)

func _on_cancel_confirmed(cancel_data: Dictionary):
	var session_id = cancel_data["session_id"]
	print("[EavesdropHub] _on_cancel_confirmed: ", session_id)
	await _cancel_session(session_id)

func _cancel_session(session_id: String):
	var success = await EavesdropManager.cancel_session(session_id)
	if success:
		await _load_active_sessions()
		_show_toast("会话已取消")
	else:
		_show_toast("取消失败")

func _on_back_pressed():
	back_pressed.emit()
	get_tree().change_scene_to_file("res://scenes/main/Hub.tscn")

func _on_refresh_pressed():
	refresh_btn.disabled = true
	refresh_btn.text = "刷新中..."
	await _load_active_sessions()
	refresh_btn.disabled = false
	refresh_btn.text = "刷新"

func _on_new_session_pressed():
	get_tree().change_scene_to_file("res://features/eavesdrop/EavesdropScene.tscn")

func _show_toast(msg: String):
	# 简单提示
	print(msg)
	if EventBus.has_signal("show_notification"):
		EventBus.emit_signal("show_notification", msg)
