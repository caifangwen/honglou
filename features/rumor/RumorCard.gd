# RumorCard.gd
extends PanelContainer

var rumor_data: Dictionary

@onready var content_label = $Content/ContentLabel
@onready var target_label = $Content/Header/TargetLabel
@onready var stage_indicator = $Content/Header/StageIndicator
@onready var countdown_label = $Content/Footer/Countdown
@onready var suppress_btn = $Content/Footer/SuppressBtn
@onready var grafted_badge = $Content/Header/GraftedBadge

func setup(data: Dictionary):
	rumor_data = data
	content_label.text = data.content
	target_label.text = "关于 " + _get_target_name(data) + " 的传言"
	
	# 根据阶段设置视觉样式
	match int(data.stage):
		1:
			stage_indicator.text = "口耳相传"
			stage_indicator.modulate = Color(0.8, 0.8, 0.5)  # 淡黄
			# 平息流言为管家特权，仅管家可见按钮
			suppress_btn.visible = (PlayerState.role_class == "steward")
		2:
			stage_indicator.text = "人尽皆知"
			stage_indicator.modulate = Color(0.9, 0.5, 0.2)  # 橙色
			suppress_btn.visible = false  # 已过自压窗口
		3:
			stage_indicator.text = "板上钉钉"
			stage_indicator.modulate = Color(0.7, 0.1, 0.1)  # 深红
			suppress_btn.visible = false
	
	# 嫁接流言显示特殊标记
	if data.get("is_grafted", false):
		grafted_badge.visible = true
	
	# 倒计时
	_update_countdown()
	
	if not suppress_btn.pressed.is_connected(_on_suppress_btn_pressed):
		suppress_btn.pressed.connect(_on_suppress_btn_pressed)

func _get_target_name(data: Dictionary) -> String:
	# 尝试多种可能的数据结构
	# 1. target_player 是数组（Supabase 外键关联返回的格式）
	if data.has("target_player") and data["target_player"] is Array and data["target_player"].size() > 0:
		if data["target_player"][0] is Dictionary and data["target_player"][0].has("display_name"):
			return data["target_player"][0]["display_name"]
	# 2. target_player 是字典
	if data.has("target_player") and data["target_player"] is Dictionary:
		if data["target_player"].has("display_name"):
			return data["target_player"]["display_name"]
	# 3. 兼容旧格式：players 嵌套结构
	if data.has("players") and data["players"] is Dictionary:
		if data["players"].has("display_name"):
			return data["players"]["display_name"]
	# 4. 如果都没有，返回占位符
	return "某人"

func _process(_delta):
	_update_countdown()

func _update_countdown():
	var next_stage_time_str = rumor_data.stage2_at if int(rumor_data.stage) == 1 else rumor_data.stage3_at
	if next_stage_time_str == null:
		countdown_label.text = ""
		return
		
	var next_stage_time = Time.get_unix_time_from_datetime_string(next_stage_time_str)
	var remaining = next_stage_time - Time.get_unix_time_from_system()
	
	if remaining > 0:
		var hours = int(remaining / 3600)
		var minutes = int(fmod(remaining, 3600) / 60)
		countdown_label.text = "还有 %d时%d分 恶化" % [hours, minutes]
	else:
		countdown_label.text = "即将发酵..."

func _on_suppress_btn_pressed():
	# 调用管家专用 RPC 平息流言
	var res = await SupabaseManager.db_rpc("steward_suppress_rumor", {
		"p_rumor_id": rumor_data.id
	})
	var ok: bool = int(res.get("code", 0)) == 200
	if ok:
		var data = res.get("data")
		if data is Dictionary and data.has("success") and data["success"] == false:
			ok = false
	
	if ok:
		queue_free()
	else:
		var err = str(res.get("error", res.get("data", {}).get("error", "未知错误")))
		push_error("平息流言失败: %s" % err)
