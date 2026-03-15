extends Control

# EavesdropHub.gd - 挂机监听中心
# 显示所有活跃会话、剩余时间、收益统计，支持取消会话

signal back_pressed()

@onready var active_sessions_container = $VBoxContainer/ActiveSessionsContainer
@onready var stats_label = $VBoxContainer/StatsLabel
@onready var back_btn = $BackButton
@onready var refresh_btn = $VBoxContainer/RefreshBtn
@onready var new_session_btn = $VBoxContainer/NewSessionBtn

@onready var cancel_confirm_dialog = $CancelConfirmDialog

const SESSION_ITEM_SCENE = preload("res://scenes/components/EavesdropSessionItem.tscn")

var _active_sessions: Array = []
var _refresh_timer: Timer

func _ready():
	_setup_ui()
	_setup_timers()
	await _load_active_sessions()

func _setup_ui():
	back_btn.pressed.connect(_on_back_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	new_session_btn.pressed.connect(_on_new_session_pressed)

func _setup_timers():
	# 每 5 秒刷新一次倒计时
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 5.0
	_refresh_timer.timeout.connect(_update_session_timers)
	_refresh_timer.autostart = true
	add_child(_refresh_timer)

func _load_active_sessions():
	# 清空现有项
	for child in active_sessions_container.get_children():
		child.queue_free()
	
	_active_sessions.clear()
	
	# 加载活跃会话
	var res = await EavesdropManager.get_active_sessions()
	_active_sessions = res
	
	# 更新统计
	_update_stats()
	
	if _active_sessions.is_empty():
		_show_no_sessions_hint()
		return
	
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
	cancel_confirm_dialog.dialog_text = "确定要取消此挂机会话吗？\n已消耗的精力的不会退还。"
	cancel_confirm_dialog.popup_centered()
	
	# 等待用户确认
	var confirmed = await cancel_confirm_dialog.confirmed
	if confirmed:
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
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _on_refresh_pressed():
	refresh_btn.disabled = true
	refresh_btn.text = "刷新中..."
	await _load_active_sessions()
	refresh_btn.disabled = false
	refresh_btn.text = "刷新"

func _on_new_session_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/EavesdropScene.tscn")

func _show_toast(msg: String):
	# 简单提示
	print(msg)
	if EventBus.has_signal("show_notification"):
		EventBus.emit_signal("show_notification", msg)
