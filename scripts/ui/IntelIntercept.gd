extends Control

# IntelIntercept.gd - 情报拦截界面
# 管家可以拦截特定玩家的情报，阻止其获取

signal back_pressed()

@onready var target_option = $VBoxContainer/TargetOption
@onready var duration_spin = $VBoxContainer/DurationSpin
@onready var confirm_btn = $VBoxContainer/ConfirmBtn
@onready var back_btn = $BackButton
@onready var stamina_label = $VBoxContainer/StaminaLabel
@onready var info_label = $VBoxContainer/InfoLabel

const COST_STAMINA = 5  # 拦截消耗 5 点精力

var _available_targets: Array = []

func _ready():
	_setup_ui()
	await _load_targets()
	_update_stamina_display()

func _setup_ui():
	back_btn.pressed.connect(_on_back_pressed)
	confirm_btn.pressed.connect(_on_confirm_pressed)
	
	# 初始化时长选择
	duration_spin.min_value = 1
	duration_spin.max_value = 12
	duration_spin.value = 4
	duration_spin.value_changed.connect(_on_duration_changed)

func _load_targets():
	target_option.clear()
	target_option.add_item("选择目标玩家", -1)
	
	var endpoint = "/rest/v1/players?id=neq.%s&select=id,character_name,role_class" % PlayerState.uid
	var res = await SupabaseManager.db_get(endpoint)
	
	if res["code"] == 200:
		_available_targets = res["data"]
		for i in range(_available_targets.size()):
			var p = _available_targets[i]
			target_option.add_item("%s (%s)" % [p["character_name"], _localize_role(p["role_class"])], i)
			target_option.set_item_metadata(i, p["id"])
	else:
		_show_toast("加载玩家列表失败")

func _localize_role(role: String) -> String:
	match role:
		"steward": return "管家"
		"master": return "主子"
		"servant": return "丫鬟"
		"elder": return "长辈"
		"guest": return "客人"
		_: return role

func _update_stamina_display():
	var current = PlayerState.get_current_stamina()
	stamina_label.text = "当前精力：%d/%d | 消耗：%d" % [current, PlayerState.stamina_max, COST_STAMINA]
	
	if current < COST_STAMINA:
		stamina_label.add_theme_color_override("font_color", Color.RED)
		confirm_btn.disabled = true
		confirm_btn.text = "精力不足"
	else:
		stamina_label.remove_theme_color_override("font_color")
		confirm_btn.disabled = false
		confirm_btn.text = "确认拦截"

func _on_duration_changed(_value):
	_update_info()

func _update_info():
	var duration = int(duration_spin.value)
	var target_idx = target_option.selected - 1  # 减去"选择目标玩家"
	
	if target_idx < 0 or target_idx >= _available_targets.size():
		info_label.text = "请选择要拦截的目标玩家"
		return
	
	var target = _available_targets[target_idx]
	info_label.text = "将拦截 [%s] 的情报获取，持续 %d 小时\n在此期间，其无法获得新的情报碎片" % [target["character_name"], duration]

func _on_confirm_pressed():
	var target_idx = target_option.selected - 1
	if target_idx < 0 or target_idx >= _available_targets.size():
		_show_toast("请先选择目标玩家")
		return
	
	var target = _available_targets[target_idx]
	var duration = int(duration_spin.value)
	
	confirm_btn.disabled = true
	confirm_btn.text = "处理中..."
	
	# 调用拦截函数
	var success = await _execute_intercept(target["id"], duration)
	
	if success:
		_show_toast("拦截成功！[%s] 在 %d 小时内无法获得情报" % [target["character_name"], duration])
		await get_tree().create_timer(1.0).timeout
		_on_back_pressed()
	else:
		_show_toast("拦截失败，请重试")
		confirm_btn.disabled = false
		confirm_btn.text = "确认拦截"

func _execute_intercept(target_uid: String, duration_hours: int) -> bool:
	# 扣除精力
	if not PlayerState.consume_stamina(COST_STAMINA):
		return false
	
	# 写入拦截记录
	var now = Time.get_unix_time_from_system()
	var end_time = now + (duration_hours * 3600)
	
	var intercept_data = {
		"game_id": GameState.current_game_id,
		"interceptor_uid": PlayerState.uid,
		"target_uid": target_uid,
		"starts_at": Time.get_datetime_string_from_unix_time(now),
		"ends_at": Time.get_datetime_string_from_unix_time(end_time),
		"status": "active"
	}
	
	var res = await SupabaseManager.db_insert("intel_intercepts", intercept_data)
	
	if res["code"] == 201:
		# 发送通知
		if EventBus.has_signal("show_notification"):
			EventBus.emit_signal("show_notification", "你的情报被管家的拦截了！")
		return true
	
	return false

func _show_toast(msg: String):
	if EventBus.has_signal("show_notification"):
		EventBus.emit_signal("show_notification", msg)

func _on_back_pressed():
	back_pressed.emit()
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")
