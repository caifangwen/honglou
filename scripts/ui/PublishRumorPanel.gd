# PublishRumorPanel.gd
extends Control

enum SourceType { INTEL_FRAGMENT, FREEWRITE }

# 测试模式开关：当设为 true 时使用本地模拟数据库（无需网络）
const USE_MOCK_DATABASE: bool = true

var selected_source_type: SourceType = SourceType.FREEWRITE
var selected_fragments: Array = []  # 最多 2 个
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
	print("[PublishRumorPanel] _ready() called")
	publish_btn.pressed.connect(_on_publish)
	close_btn.pressed.connect(hide)
	tab_container.tab_changed.connect(_on_tab_changed)
	target_selector.item_selected.connect(_on_target_selected)
	_load_players()
	_load_intel_fragments()
	print("[PublishRumorPanel] Panel initialized")

func _on_tab_changed(tab: int):
	selected_source_type = SourceType.INTEL_FRAGMENT if tab == 0 else SourceType.FREEWRITE

func _on_target_selected(index: int):
	if index > 0:
		selected_target_uid = target_selector.get_item_metadata(index)
	else:
		selected_target_uid = ""

func _load_players():
	target_selector.clear()
	target_selector.add_item("选择流言目标...", 0)

	if PlayerState.current_game_id == "":
		print("[PublishRumorPanel] Warning: current_game_id is empty")
		return

	var players = await SupabaseManager.query("players", {"current_game_id": PlayerState.current_game_id})
	for p in players:
		if p.id != PlayerState.player_db_id:
			target_selector.add_item(p.display_name, 1)
			target_selector.set_item_metadata(target_selector.get_item_count() - 1, p.id)

func _load_intel_fragments():
	for child in fragment_list.get_children():
		child.queue_free()

	if PlayerState.player_db_id == "":
		return

	var fragments = await SupabaseManager.query(
		"intel_fragments",
		{"owner_uid": PlayerState.player_db_id, "is_used": false}
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
	print("[PublishRumorPanel] _on_publish() called")
	print("[PublishRumorPanel] access_token: ", SupabaseManager.access_token.substr(0, 20) + "..." if SupabaseManager.access_token != "" else "EMPTY")
	print("[PublishRumorPanel] player_db_id: ", PlayerState.player_db_id)
	print("[PublishRumorPanel] current_game_id: ", PlayerState.current_game_id)

	# Prevent multiple simultaneous calls
	if publish_btn.disabled:
		print("[PublishRumorPanel] Publish already in progress, ignoring")
		return

	# 确保目标已选择
	if target_selector.selected <= 0:
		EventBus.show_notification.emit("请选择流言目标")
		return

	selected_target_uid = target_selector.get_item_metadata(target_selector.selected)

	if selected_target_uid == "":
		EventBus.show_notification.emit("请选择有效的流言目标")
		return

	# 校验精力
	if PlayerState.stamina < 5:
		EventBus.show_notification.emit("精力不足，无法发布流言")
		return

	# 构造流言数据
	var content = ""
	var source_type_str = ""
	var intel_fragment_ids = []

	if selected_source_type == SourceType.FREEWRITE:
		content = freewrite_input.text.strip_edges()
		if content.length() < 2 or content.length() > 150:
			EventBus.show_notification.emit("流言内容需在 2–150 字之间")
			return
		source_type_str = "freewrite"
	else:
		if selected_fragments.is_empty():
			EventBus.show_notification.emit("请至少选择一条情报碎片")
			return
		source_type_str = "intel_fragment"
		intel_fragment_ids = selected_fragments.map(func(f): return f.id)
		# 合并碎片内容
		for f in selected_fragments:
			if content != "":
				content += "；又听闻："
			content += f.content

	# 计算时间
	var now = Time.get_unix_time_from_system()
	var stage2_at = now + 6 * 3600  # 6 小时后
	var stage3_at = now + 12 * 3600  # 12 小时后

	# 检查嫁接
	var is_grafted = false
	var credibility = 0.5
	if selected_source_type == SourceType.INTEL_FRAGMENT and selected_fragments.size() == 2:
		var uid_a = selected_fragments[0].about_player_id
		var uid_b = selected_fragments[1].about_player_id
		if uid_a == uid_b and uid_a == selected_target_uid:
			is_grafted = true
			credibility = 2.0
		else:
			credibility = 1.5
	elif selected_source_type == SourceType.INTEL_FRAGMENT:
		credibility = 1.5

	# 直接插入流言到数据库
	var rumor_payload = {
		"game_id": PlayerState.current_game_id,
		"publisher_uid": PlayerState.player_db_id,
		"target_uid": selected_target_uid,
		"content": content,
		"source_type": source_type_str,
		"is_grafted": is_grafted,
		"credibility": credibility,
		"stage": 1,
		"published_at": Time.get_datetime_string_from_unix_time(int(now)),
		"stage2_at": Time.get_datetime_string_from_unix_time(int(stage2_at)),
		"stage3_at": Time.get_datetime_string_from_unix_time(int(stage3_at))
	}

	if intel_fragment_ids.size() > 0:
		rumor_payload["intel_fragment_ids"] = intel_fragment_ids

	print("[PublishRumorPanel] Inserting rumor with payload: ", rumor_payload)

	publish_btn.disabled = true
	publish_btn.text = "发布中..."

	var result
	if USE_MOCK_DATABASE:
		print("[PublishRumorPanel] Using MOCK database (test mode)")
		result = await MockDatabase.mock_insert_rumor(rumor_payload)
	else:
		print("[PublishRumorPanel] Using real Supabase database")
		result = await SupabaseManager.db_insert("rumors", rumor_payload)

	print("[PublishRumorPanel] Insert result code: ", result.get("code", "N/A"))
	print("[PublishRumorPanel] Insert result data: ", result.get("data", "N/A"))
	print("[PublishRumorPanel] Insert result error: ", result.get("error", "N/A"))

	publish_btn.text = "发布流言"

	if result["code"] == 201 or result["code"] == 200:
		# 扣除精力
		if USE_MOCK_DATABASE:
			await MockDatabase.mock_update_player(PlayerState.player_db_id, {"stamina": PlayerState.stamina - 5})
		else:
			await SupabaseManager.db_update(
				"players",
				"id=eq." + PlayerState.player_db_id,
				{"stamina": PlayerState.stamina - 5}
			)

		# 标记碎片为已使用
		if intel_fragment_ids.size() > 0:
			for f in selected_fragments:
				if USE_MOCK_DATABASE:
					print("[PublishRumorPanel] Mock: Mark fragment %s as used" % f.id)
				else:
					await SupabaseManager.db_update(
						"intel_fragments",
						"id=eq." + f.id,
						{"is_used": true}
					)

		EventBus.show_notification.emit("流言已悄悄散出，坐等发酵...")
		PlayerState.stamina -= 5
		hide()
		# 发送信号通知列表刷新
		var rumor_data = result["data"] if result["data"] is Array else result["data"]
		EventBus.rumor_published.emit(rumor_data)
	else:
		var err = "未知错误"
		if result.has("error"):
			err = result["error"]
		elif result.has("data") and result["data"] is Dictionary:
			err = str(result["data"].get("error", "未知错误"))
		EventBus.show_notification.emit("发布失败：" + err)
		publish_btn.disabled = false
