extends Control

# MessageCard.gd
# 负责单条消息卡片的 UI 呈现和交互

@onready var avatar: TextureRect = $HBox/Avatar
@onready var sender_label: Label = $HBox/VBox/Header/SenderLabel
@onready var type_label: Label = $HBox/VBox/Header/TypeLabel
@onready var time_label: Label = $HBox/VBox/Header/TimeLabel
@onready var content_label: Label = $HBox/VBox/ContentLabel
@onready var attachments_label: Label = $HBox/VBox/AttachmentsLabel
@onready var unread_indicator: ColorRect = $UnreadIndicator
@onready var reaction_buttons: HBoxContainer = $HBox/VBox/ReactionButtons
@onready var action_buttons: HBoxContainer = $HBox/VBox/ActionButtons

# 流言专用组件
@onready var rumor_panel: Control = $HBox/VBox/RumorPanel
@onready var rumor_bar: ProgressBar = $HBox/VBox/RumorPanel/ProgressBar
@onready var rumor_timer_label: Label = $HBox/VBox/RumorPanel/TimerLabel

var message_id: String = ""
var message_data: Dictionary = {}

func setup(data: Dictionary) -> void:
	message_data = data
	message_id = data.get("id", "")
	
	# 基础信息
	var sender_info = data.get("sender", {})
	var s_name = sender_info.get("character_name", "未知")
	if s_name == "未知":
		s_name = sender_info.get("display_name", "未知")
	
	sender_label.text = s_name
	type_label.text = _get_type_display_name(data.get("message_type", ""))
	content_label.text = data.get("content", "")
	time_label.text = _format_time(data.get("created_at", ""))
	
	# 未读状态
	unread_indicator.visible = not data.get("is_read", false)
	
	# 附件
	var attachments = data.get("attachments", [])
	if attachments.size() > 0:
		attachments_label.text = "[附: 碎片×%d]" % attachments.size()
		attachments_label.show()
	else:
		attachments_label.hide()
	
	# 流言特殊处理
	if data.get("message_type") == "rumor":
		_setup_rumor_ui(data)
		sender_label.text = "匿名" # 流言来源匿名
	else:
		rumor_panel.hide()
	
	# 根据权限显示操作按钮
	_setup_action_buttons(data)

func _get_type_display_name(type: String) -> String:
	match type:
		"private": return "私信"
		"rumor": return "流言"
		"batch_order": return "批条"
		"system": return "系统"
		"petition": return "谏言"
		"accusation": return "举报"
		_: return "通知"

func _format_time(iso_time: String) -> String:
	# 简化的时间格式化，实际项目中可能需要更复杂的转换
	# 比如 "2小时前", "昨日巳时" 等
	return iso_time.substr(11, 5) # 仅返回 HH:MM

func _setup_rumor_ui(data: Dictionary) -> void:
	rumor_panel.show()
	var stage = data.get("stage", 0)
	var created_at = Time.get_unix_time_from_datetime_string(data.get("created_at", ""))
	var now = Time.get_unix_time_from_system()
	var elapsed = now - created_at
	
	# 假设发酵总时长 24 小时 (86400秒)
	var total_time = 86400.0
	rumor_bar.value = (elapsed / total_time) * 100
	
	# 颜色变化：绿色 (0-6h) / 橙色 (6-12h) / 红色 (12h+)
	var hours = elapsed / 3600.0
	if hours < 6:
		rumor_bar.modulate = Color.GREEN
	elif hours < 12:
		rumor_bar.modulate = Color.ORANGE
	else:
		rumor_bar.modulate = Color.RED
	
	if hours >= 12:
		rumor_timer_label.text = "已成实质处罚"
		# 禁用压下流言按钮
	else:
		rumor_timer_label.text = "发酵中 %dh/24h" % int(hours)

func _setup_action_buttons(data: Dictionary) -> void:
	# 清空旧按钮
	for child in action_buttons.get_children():
		child.queue_free()
		
	var type = data.get("message_type", "")
	
	# 私信/传话按钮 (仅丫鬟可见)
	if PlayerState.role_class == "servant" and type == "private" and not data.get("is_intercepted", false):
		var btn_relay = Button.new()
		btn_relay.text = "传话"
		btn_relay.pressed.connect(_on_relay_pressed)
		action_buttons.add_child(btn_relay)
		
		var btn_intercept = Button.new()
		btn_intercept.text = "截留"
		btn_intercept.pressed.connect(_on_intercept_pressed)
		action_buttons.add_child(btn_intercept)
	
	# 流言按钮
	if type == "rumor":
		if data.get("receiver_uid") == PlayerState.player_db_id: # 被流言攻击的目标
			var btn_suppress = Button.new()
			btn_suppress.text = "压下 (-10气数)"
			btn_suppress.disabled = data.get("stage", 0) > 0
			btn_suppress.pressed.connect(_on_suppress_pressed)
			action_buttons.add_child(btn_suppress)
		
		if PlayerState.role_class == "steward": # 管家平息
			var btn_quell = Button.new()
			btn_quell.text = "平息"
			btn_quell.pressed.connect(_on_quell_pressed)
			action_buttons.add_child(btn_quell)

# --- 信号处理 ---

func _on_relay_pressed() -> void:
	# 打开写信面板，预填传话逻辑
	pass

func _on_intercept_pressed() -> void:
	# 调用 InboxManager.intercept_message
	pass

func _on_suppress_pressed() -> void:
	# 调用 InboxManager.suppress_rumor
	pass

func _on_quell_pressed() -> void:
	# 调用 InboxManager.quell_rumor
	pass
