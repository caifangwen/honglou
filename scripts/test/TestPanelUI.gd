extends Control

# TestPanelUI.gd

@onready var log_label: RichTextLabel = $VBox/LogPanel/LogLabel
@onready var harness: Node = $MaidSystemTestHarness

func _ready() -> void:
	harness.test_log.connect(_on_test_log)
	log_label.append_text("[color=yellow]=== 丫鬟系统测试面板 ===[/color]\n")

func _on_test_log(msg: String) -> void:
	log_label.append_text(msg + "\n")
	# 自动滚动到底部
	var scroll = log_label.get_v_scroll_bar()
	if scroll:
		scroll.value = scroll.max_value

func _on_SetupBtn_pressed() -> void:
	await harness.setup_test_environment()

func _on_TestIntelBtn_pressed() -> void:
	await harness.test_intel_generation()

func _on_TestRumorBtn_pressed() -> void:
	await harness.test_rumor_fermentation()

func _on_TestRedemptionBtn_pressed() -> void:
	await harness.test_redemption_achievement()

func _on_TestPartnershipBtn_pressed() -> void:
	await harness.test_partnership_monitoring()

func _on_RunAllBtn_pressed() -> void:
	await harness.run_all_tests()

func _on_ResetBtn_pressed() -> void:
	await harness.reset_test_data()

func _on_TimeSkipBtn_pressed() -> void:
	# 模拟流言发酵的时间跳过（手动触发一次检查）
	log_label.append_text("正在模拟时间跳过，触发流言发酵检查...\n")
	# 这里简单查询所有当前局的活跃流言并尝试发酵
	var res = await SupabaseManager.db_get("/rest/v1/rumors?game_id=eq.%s&ferment_stage=lt.3&is_suppressed=eq.false&select=id" % harness.test_game_id)
	if res["code"] == 200:
		for rumor in res["data"]:
			await harness.ferment_check_now(rumor["id"])
		log_label.append_text("流言检查完成。\n")
