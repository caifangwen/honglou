extends Control

# InboxUI.gd
# 门房收件箱主界面逻辑

const MessageCardScene = preload("res://scenes/components/MessageCard.tscn")
const ComposePanelScene = preload("res://scenes/components/ComposePanel.tscn")

@onready var message_list: VBoxContainer = $ScrollContainer/MessageList
@onready var tab_group: HBoxContainer = $Tabs
@onready var unread_count_label: Label = $Header/UnreadCount
@onready var btn_compose: Button = $Header/BtnCompose
@onready var empty_state: Label = $EmptyState

var current_tab: String = "all"
var compose_panel: Control = null

func _ready() -> void:
	# 初始加载
	load_messages("all")
	
	# 连接 tab 按钮信号
	for btn in tab_group.get_children():
		if btn is Button:
			btn.pressed.connect(_on_tab_pressed.bind(btn.name.to_lower()))
	
	# 写信按钮
	btn_compose.pressed.connect(_on_compose_pressed)
	
	# 实时订阅
	InboxManager.subscribe_to_inbox()
	InboxManager.new_message_received.connect(_on_new_message_received)
	
	# 音效：翻阅信件
	# AudioManager.play_sfx("res://assets/sfx/paper_rustle.wav")

func load_messages(tab: String) -> void:
	current_tab = tab
	_clear_list()
	
	var messages = await InboxManager.load_inbox(tab)
	if messages.is_empty():
		empty_state.show()
		empty_state.text = "门房清净，暂无来信。"
	else:
		empty_state.hide()
		_display_messages(messages)
	
	_update_unread_count(messages)

func _clear_list() -> void:
	for child in message_list.get_children():
		child.queue_free()

func _display_messages(messages: Array) -> void:
	for data in messages:
		var card = MessageCardScene.instantiate()
		message_list.add_child(card)
		card.setup(data)
		
		# 动效：卡片从右侧滑入
		card.position.x += 100
		var tween = create_tween()
		tween.tween_property(card, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_SINE)

func _update_unread_count(messages: Array) -> void:
	var unread = 0
	for m in messages:
		if not m.get("is_read", false):
			unread += 1
			
	if unread > 0:
		unread_count_label.text = "未读 🔴 %d" % unread
		unread_count_label.show()
	else:
		unread_count_label.hide()

func _on_tab_pressed(tab_name: String) -> void:
	# 处理 tab 映射，如 "全部" -> "all"
	var tab_map = {
		"全部": "all",
		"私信": "private",
		"批条": "batch_order",
		"流言": "rumor",
		"系统": "system"
	}
	load_messages(tab_map.get(tab_name, tab_name))

func _on_compose_pressed() -> void:
	if not compose_panel:
		compose_panel = ComposePanelScene.instantiate()
		add_child(compose_panel)
	compose_panel.show()

func _on_new_message_received(data: Dictionary) -> void:
	# 实时更新 UI
	if current_tab == "all" or data.get("message_type") == current_tab:
		var card = MessageCardScene.instantiate()
		message_list.add_child(card)
		message_list.move_child(card, 0) # 置顶
		card.setup(data)
		
		# 弹出横幅通知
		# NotifyBanner.show_message("您收到一封帖子")
		
		# 刷新未读计数
		_update_unread_count(await InboxManager.load_inbox(current_tab))

func _on_BackBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")
