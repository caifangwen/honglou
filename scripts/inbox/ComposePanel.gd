extends Control

# ComposePanel.gd
# 负责写信界面的 UI 交互和发信逻辑

@onready var receiver_search: LineEdit = $VBox/ReceiverBox/ReceiverSearch
@onready var receiver_list: ItemList = $VBox/ReceiverBox/ReceiverList
@onready var content_edit: TextEdit = $VBox/ContentBox/ContentEdit
@onready var stamina_cost_label: Label = $VBox/HBox/StaminaCostLabel
@onready var attachments_list: HBoxContainer = $VBox/AttachmentsList
@onready var btn_send: Button = $VBox/HBox/BtnSend
@onready var btn_cancel: Button = $VBox/HBox/BtnCancel

# 丫鬟专属选项
@onready var servant_options: VBoxContainer = $VBox/ServantOptions
@onready var check_tamper: CheckBox = $VBox/ServantOptions/CheckTamper
@onready var tamper_edit: TextEdit = $VBox/ServantOptions/TamperEdit
@onready var check_intercept: CheckBox = $VBox/ServantOptions/CheckIntercept

var selected_receiver_uid: String = ""
var message_type: String = "private" # 默认私信

func _ready() -> void:
	# 初始状态
	servant_options.visible = PlayerState.role_class == "servant"
	_update_stamina_hint()
	
	# 信号连接
	receiver_search.text_changed.connect(_on_receiver_search_changed)
	receiver_list.item_selected.connect(_on_receiver_selected)
	btn_send.pressed.connect(_on_send_pressed)
	btn_cancel.pressed.connect(_on_cancel_pressed)
	
	# 监听丫鬟篡改/截留勾选，更新文案和精力
	check_tamper.toggled.connect(_on_servant_action_toggled.bind(check_tamper))
	check_intercept.toggled.connect(_on_servant_action_toggled.bind(check_intercept))
	
	# 默认加载联系人
	_load_initial_contacts()

func _load_initial_contacts() -> void:
	# 加载当前局内所有其他玩家作为初始联系人
	var game_id = PlayerState.current_game_id
	if game_id == "":
		return
		
	var endpoint = "/rest/v1/players?game_id=eq.%s&id=neq.%s&select=id,display_name,character_name" % [game_id, PlayerState.player_db_id]
	var res = await SupabaseManager.db_get(endpoint)
	if res["code"] == 200:
		receiver_list.clear()
		for player in res["data"]:
			var label = "%s (%s)" % [player["display_name"], player["character_name"]]
			receiver_list.add_item(label)
			receiver_list.set_item_metadata(receiver_list.get_item_count() - 1, player["id"])
		
		if not res["data"].is_empty():
			receiver_list.show()

func _update_stamina_hint() -> void:
	var cost = 1 # 默认私信 1 点
	if message_type == "rumor":
		cost = 5
	elif message_type == "batch_order":
		cost = 2
	
	# 丫鬟特殊动作：截留不消耗精力
	if check_intercept.button_pressed:
		cost = 0
		
	stamina_cost_label.text = "预计消耗精力: %d 点" % cost
	
	# 若当前精力不足，按钮变灰
	btn_send.disabled = PlayerState.get_current_stamina() < cost

func _on_receiver_search_changed(new_text: String) -> void:
	# 搜索玩家逻辑（模糊查询）
	# 调用 SupabaseManager 查询 players 表
	if new_text.length() == 0:
		_load_initial_contacts()
		return
		
	if new_text.length() < 2:
		# 仅输入一个字符时暂不搜索
		return
	
	var endpoint = "/rest/v1/players?display_name=ilike.*%s*&game_id=eq.%s&id=neq.%s&select=id,display_name,character_name" % [new_text, PlayerState.current_game_id, PlayerState.player_db_id]
	var res = await SupabaseManager.db_get(endpoint)
	if res["code"] == 200:
		receiver_list.clear()
		if res["data"].is_empty():
			# receiver_list.hide() # 不要隐藏，让用户知道没搜到
			return
			
		receiver_list.show()
		for player in res["data"]:
			var label = "%s (%s)" % [player["display_name"], player["character_name"]]
			receiver_list.add_item(label)
			receiver_list.set_item_metadata(receiver_list.get_item_count() - 1, player["id"])

func _on_receiver_selected(index: int) -> void:
	selected_receiver_uid = receiver_list.get_item_metadata(index)
	receiver_search.text = receiver_list.get_item_text(index)
	receiver_list.hide()

func _on_send_pressed() -> void:
	if PlayerState.player_db_id == "":
		_show_error("无法识别发送者身份，请重新登录。")
		push_error("[ComposePanel] PlayerState.player_db_id is empty!")
		return
		
	if selected_receiver_uid == "":
		_show_error("请先从列表中选择收件人。")
		return
		
	if content_edit.text.strip_edges() == "" and not check_intercept.button_pressed:
		_show_error("信件内容不能为空。")
		return
	
	# 禁用发送按钮，防止重复点击
	btn_send.disabled = true
	
	# 业务逻辑分支
	var result = {}
	
	# 丫鬟动作
	if check_intercept.button_pressed:
		_show_error("截留功能需要先选择要截留的信件。")
		btn_send.disabled = false
		return
	elif check_tamper.button_pressed:
		_show_error("传话功能需要先选择要传达的原始信件。")
		btn_send.disabled = false
		return
	else:
		# 普通发信
		result = await InboxManager.send_private_message(selected_receiver_uid, content_edit.text)
	
	if result.get("success", false):
		_show_success("信件已寄出。")
		# 延迟一下再隐藏，让用户看到成功提示
		await get_tree().create_timer(1.0).timeout
		hide()
		# 清空内容以便下次使用
		content_edit.text = ""
		selected_receiver_uid = ""
		receiver_search.text = ""
		_load_initial_contacts()
	else:
		_show_error(result.get("error", "发送失败。"))
		btn_send.disabled = false

func _on_cancel_pressed() -> void:
	hide()

func _on_servant_action_toggled(button_pressed: bool, source: CheckBox) -> void:
	# 互斥处理：如果勾选了其中一个，则取消勾选另一个
	if button_pressed:
		if source == check_tamper:
			check_intercept.set_pressed_no_signal(false)
		elif source == check_intercept:
			check_tamper.set_pressed_no_signal(false)
	
	tamper_edit.visible = check_tamper.button_pressed
	_update_stamina_hint()

func _show_error(msg: String) -> void:
	# 简单的错误提示，实际可用弹出框
	push_warning("[ComposePanel] " + msg)
	# 尝试在 UI 上显示错误（如果有错误提示 Label 的话，此处假设我们增加一个）
	# 如果场景中没有 ErrorLabel，这里可以打印到输出台
	# 为了让用户看到，我们可以利用现有的 stamina_cost_label 临时显示
	var old_text = stamina_cost_label.text
	var old_color = stamina_cost_label.get_theme_color("font_color")
	stamina_cost_label.text = msg
	stamina_cost_label.add_theme_color_override("font_color", Color.RED)
	await get_tree().create_timer(3.0).timeout
	stamina_cost_label.text = old_text
	stamina_cost_label.add_theme_color_override("font_color", old_color)

func _show_success(msg: String) -> void:
	print("[ComposePanel] " + msg)
	# 同样可以在 UI 上显示成功信息
	var old_text = stamina_cost_label.text
	var old_color = stamina_cost_label.get_theme_color("font_color")
	stamina_cost_label.text = msg
	stamina_cost_label.add_theme_color_override("font_color", Color.GREEN)
	await get_tree().create_timer(2.0).timeout
	stamina_cost_label.text = old_text
	stamina_cost_label.add_theme_color_override("font_color", old_color)
