# RumorBoardUI.gd
extends Control

const RUMOR_CARD = preload("res://scenes/RumorCard.tscn")
const PUBLISH_PANEL = preload("res://scenes/PublishRumorPanel.tscn")

@onready var rumor_list_container = $ActiveRumors/RumorList
@onready var internal_heat_bar = $Header/InternalHeatBar
@onready var publish_btn = $PublishPanel/PublishBtn
@onready var back_btn = $Header/BackBtn

func _ready():
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
	_load_rumors()

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _on_publish_btn_pressed():
	var panel = PUBLISH_PANEL.instantiate()
	add_child(panel)

func _load_rumors():
	# 清空现有卡片
	for child in rumor_list_container.get_children():
		child.queue_free()
		
	# 1. 加载阶段 2 及以上的公开流言
	var rumors = await SupabaseManager.query("rumors", {"stage": 2, "is_suppressed": false})
	# 2. 加载阶段 3 的流言
	var rumors_stage3 = await SupabaseManager.query("rumors", {"stage": 3, "is_suppressed": false})
	rumors.append_array(rumors_stage3)
	
	# 3. 加载针对自己的阶段 1 流言
	var personal_rumors = await SupabaseManager.query("rumors", {"target_uid": PlayerState.player_db_id, "stage": 1, "is_suppressed": false})
	rumors.append_array(personal_rumors)
	
	for r in rumors:
		_add_rumor_card(r)

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
