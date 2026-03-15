# RumorBoardUI.gd
extends Control

const RUMOR_CARD = preload("res://scenes/RumorCard.tscn")
const PUBLISH_PANEL = preload("res://scenes/PublishRumorPanel.tscn")

# 测试模式开关：与 PublishRumorPanel 保持一致
const USE_MOCK_DATABASE: bool = true

var _publish_panel_instance: Control = null

@onready var rumor_list_container = $ActiveRumors/RumorList
@onready var internal_heat_bar = $Header/InternalHeatBar
@onready var publish_btn = $PublishPanel/PublishBtn
@onready var back_btn = $Header/BackBtn

func _ready():
	print("[RumorBoardUI] _ready() called")
	_load_rumors()
	_subscribe_to_rumors()

	if not back_btn.pressed.is_connected(_on_back_pressed):
		back_btn.pressed.connect(_on_back_pressed)
	if not publish_btn.pressed.is_connected(_on_publish_btn_pressed):
		publish_btn.pressed.connect(_on_publish_btn_pressed)

	# 监听内耗值变化
	GameState.conflict_changed.connect(_on_conflict_changed)
	_on_conflict_changed(GameState.internal_conflict)

	# 监听流言发布成功信号，刷新列表
	if not EventBus.rumor_published.is_connected(_on_rumor_published):
		EventBus.rumor_published.connect(_on_rumor_published)

func _on_rumor_published(_data: Dictionary):
	print("[RumorBoardUI] rumor_published signal received, data: ", _data)
	_load_rumors()

func _on_publish_panel_visibility_changed():
	if _publish_panel_instance and not _publish_panel_instance.visible:
		# Panel was hidden, optionally refresh rumors
		_load_rumors()

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _on_publish_btn_pressed():
	# Reuse existing panel or create new one
	if _publish_panel_instance == null or not is_instance_valid(_publish_panel_instance):
		_publish_panel_instance = PUBLISH_PANEL.instantiate()
		add_child(_publish_panel_instance)
		_publish_panel_instance.hide()
		# Connect to panel's hidden signal to clean up when closed
		_publish_panel_instance.visibility_changed.connect(_on_publish_panel_visibility_changed)
	
	_publish_panel_instance.visible = true
	_publish_panel_instance.set_process_input(true)

func _load_rumors():
	print("[RumorBoardUI] _load_rumors() called")
	# 清空现有卡片
	for child in rumor_list_container.get_children():
		child.queue_free()

	var rumors: Array = []
	
	if USE_MOCK_DATABASE:
		# 使用模拟数据库
		print("[RumorBoardUI] Using MOCK database")
		var all_mock_rumors = MockDatabase.get_mock_rumors()
		# 过滤 stage 1 的流言（模拟场景）
		for r in all_mock_rumors:
			if r.get("stage", 1) == 1 and not r.get("is_suppressed", false):
				rumors.append(r)
		print("[RumorBoardUI] Loaded %d mock rumors" % rumors.size())
	else:
		# 使用真实 Supabase 查询
		# 1. 加载阶段 2 及以上的公开流言
		var stage2_rumors = await _query_rumors_with_players({"stage": 2, "is_suppressed": false})
		print("[RumorBoardUI] Loaded stage 2 rumors: ", stage2_rumors.size())
		# 2. 加载阶段 3 的流言
		var stage3_rumors = await _query_rumors_with_players({"stage": 3, "is_suppressed": false})
		print("[RumorBoardUI] Loaded stage 3 rumors: ", stage3_rumors.size())
		rumors.append_array(stage2_rumors)
		rumors.append_array(stage3_rumors)

		# 3. 加载针对自己的阶段 1 流言
		var personal_rumors = await _query_rumors_with_players({"target_uid": PlayerState.player_db_id, "stage": 1, "is_suppressed": false})
		print("[RumorBoardUI] Loaded personal stage 1 rumors: ", personal_rumors.size())
		rumors.append_array(personal_rumors)

		# 4. 加载自己发布的阶段 1 流言
		var my_rumors = await _query_rumors_with_players({"publisher_uid": PlayerState.player_db_id, "stage": 1, "is_suppressed": false})
		print("[RumorBoardUI] Loaded my stage 1 rumors: ", my_rumors.size())
		for r in my_rumors:
			var exists = false
			for existing in rumors:
				if existing.id == r.id:
					exists = true
					break
			if not exists:
				rumors.append(r)

	print("[RumorBoardUI] Total rumors to display: ", rumors.size())
	for r in rumors:
		_add_rumor_card(r)

func _query_rumors_with_players(filters: Dictionary) -> Array:
	# 构建带 select 的查询，关联 players 表获取目标玩家信息
	var endpoint = "/rest/v1/rumors?select=*,target_player:players!target_uid(display_name,id)"
	for key in filters.keys():
		endpoint += "&" + key + "=eq." + str(filters[key])
	
	print("[RumorBoardUI] Query endpoint: ", endpoint)
	
	var res = await SupabaseManager.db_get(endpoint)
	print("[RumorBoardUI] Query result code: ", res.get("code", "N/A"))
	print("[RumorBoardUI] Query result data count: ", res["data"].size() if res.has("data") and res["data"] is Array else 0)
	
	return res["data"] if res["code"] == 200 and res.has("data") else []

func _add_rumor_card(data: Dictionary):
	# 防止重复
	for child in rumor_list_container.get_children():
		if child is PanelContainer and child.rumor_data.id == data.id:
			child.setup(data) # 更新
			return
			
	var card = RUMOR_CARD.instantiate()
	rumor_list_container.add_child(card)
	card.setup(data)

func _remove_rumor_card(rumor_id: String):
	for child in rumor_list_container.get_children():
		if child is PanelContainer and child.rumor_data.id == rumor_id:
			child.queue_free()
			break

func _subscribe_to_rumors():
	# 监听流言广场的变化（stage >= 2 的公开流言）
	SupabaseManager.channel("rumors:public") \
		.on("postgres_changes", \
			{"event": "*", "schema": "public", "table": "rumors", \
			 "filter": "stage=gte.2"}, \
			_on_rumor_changed \
		) \
		.subscribe()
	
	# 监听针对自己的流言（私密）
	SupabaseManager.channel("rumors:personal") \
		.on("postgres_changes", \
			{"event": "INSERT", "schema": "public", "table": "rumors", \
			 "filter": "target_uid=eq." + PlayerState.player_db_id}, \
			_on_targeted_by_rumor \
		) \
		.subscribe()

func _on_rumor_changed(payload: Dictionary):
	match payload.eventType:
		"INSERT":
			_add_rumor_card(payload.new)
		"UPDATE":
			if payload.new.is_suppressed:
				_remove_rumor_card(payload.new.id)
			else:
				_add_rumor_card(payload.new)
		"DELETE":
			_remove_rumor_card(payload.old.id)

func _on_targeted_by_rumor(payload: Dictionary):
	# 收到针对自己的流言时推送通知
	EventBus.emit_signal("show_notification", "有暗流涌动: 有人正在私下议论你，注意防范...")
	_add_rumor_card(payload.new)

func _on_conflict_changed(new_value: float):
	if internal_heat_bar:
		internal_heat_bar.value = new_value
