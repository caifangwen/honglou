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
			suppress_btn.visible = (data.target_uid == PlayerState.player_db_id)
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
	if data.has("players") and data["players"].has("display_name"):
		return data["players"]["display_name"]
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
	# 弹出确认对话框
	# 假设有一个全局 ConfirmDialog，如果没有则直接调用
	var result = await SupabaseManager.invoke_function("suppress-rumor", {"rumor_id": rumor_data.id})
	if result.get("success", false):
		PlayerState.qi_points -= 10
		queue_free()
	else:
		print("压制失败: ", result.get("error", "未知错误"))
