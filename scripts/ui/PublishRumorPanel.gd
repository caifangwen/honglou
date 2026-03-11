# PublishRumorPanel.gd
extends Control

enum SourceType { INTEL_FRAGMENT, FREEWRITE }

var selected_source_type: SourceType = SourceType.FREEWRITE
var selected_fragments: Array = []  # 最多2个
var selected_target_uid: String = ""

@onready var tab_container = $Panel/TabContainer
@onready var fragment_list = $Panel/TabContainer/FromIntel/FragmentList
@onready var freewrite_input = $Panel/TabContainer/FreeWrite/ContentInput
@onready var target_selector = $Panel/TargetSelector
@onready var stamina_label = $Panel/StaminaCost/Label
@onready var graft_hint = $Panel/GraftHint
@onready var publish_btn = $Panel/PublishBtn
@onready var close_btn = $Panel/CloseBtn

func _ready():
	stamina_label.text = "发布消耗：5点精力"
	publish_btn.pressed.connect(_on_publish)
	close_btn.pressed.connect(hide)
	tab_container.tab_changed.connect(_on_tab_changed)
	_load_players()
	_load_intel_fragments()

func _on_tab_changed(tab: int):
	selected_source_type = SourceType.INTEL_FRAGMENT if tab == 0 else SourceType.FREEWRITE

func _load_players():
	target_selector.clear()
	target_selector.add_item("选择流言目标...", 0)
	var players = await SupabaseManager.query("players", {"current_game_id": PlayerState.current_game_id})
	for p in players:
		if p.id != PlayerState.player_db_id:
			target_selector.add_item(p.display_name, 1)
			target_selector.set_item_metadata(target_selector.get_item_count() - 1, p.id)

func _load_intel_fragments():
	for child in fragment_list.get_children():
		child.queue_free()
		
	var fragments = await SupabaseManager.query(
		"intel_fragments", 
		{"owner_id": PlayerState.player_db_id, "is_used": false}
	)
	
	for f in fragments:
		var btn = CheckBox.new()
		btn.text = f.content.left(20) + "..."
		btn.toggled.connect(_on_fragment_toggled.bind(f))
		fragment_list.add_child(btn)

func _on_fragment_toggled(toggled: bool, fragment: Dictionary):
	if toggled:
		if selected_fragments.size() >= 2:
			# 撤销选中
			for child in fragment_list.get_children():
				if child is CheckBox and child.text.begins_with(fragment.content.left(20)):
					child.button_pressed = false
					break
			return
		selected_fragments.append(fragment)
	else:
		selected_fragments.erase(fragment)
	
	_check_graft_availability()

func _check_graft_availability():
	if selected_fragments.size() == 2:
		var uid_a = selected_fragments[0].about_player_id
		var uid_b = selected_fragments[1].about_player_id
		if uid_a == uid_b and uid_a != null:
			graft_hint.visible = true
			graft_hint.text = "⚡ 可嫁接！伤害翻倍，难以证伪"
			# 自动选择目标
			for i in range(target_selector.get_item_count()):
				if target_selector.get_item_metadata(i) == uid_a:
					target_selector.select(i)
					selected_target_uid = uid_a
					break
		else:
			graft_hint.visible = false
	else:
		graft_hint.visible = false

func _on_publish():
	# 获取选中的目标 UID
	if selected_target_uid == "" and target_selector.get_selected_id() > 0:
		selected_target_uid = target_selector.get_item_metadata(target_selector.selected)
		
	if selected_target_uid == "":
		print("请选择流言目标")
		return

	# 校验精力
	if PlayerState.stamina < 5:
		print("精力不足，无法发布流言")
		return
	
	# 构造请求
	var payload = {
		"game_id": PlayerState.current_game_id,
		"target_uid": selected_target_uid,
		"source_type": "freewrite" if selected_source_type == SourceType.FREEWRITE else "intel_fragment",
	}
	
	if selected_source_type == SourceType.FREEWRITE:
		var content = freewrite_input.text.strip_edges()
		if content.length() == 0 or content.length() > 150:
			print("流言内容需在1–150字之间")
			return
		payload["content"] = content
	else:
		if selected_fragments.is_empty():
			print("请至少选择一条情报碎片")
			return
		payload["intel_fragment_ids"] = selected_fragments.map(func(f): return f.id)
	
	publish_btn.disabled = true
	var result = await SupabaseManager.invoke_function("publish-rumor", payload)
	
	if result.get("success", false):
		print("流言已悄悄散出，坐等发酵...")
		PlayerState.stamina -= 5
		hide()
		# 发送信号通知列表刷新
		EventBus.emit_signal("special_event_triggered", "rumor_published")
	else:
		print("发布失败：" + result.get("error", "未知错误"))
		publish_btn.disabled = false
