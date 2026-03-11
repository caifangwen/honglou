extends MarginContainer

# 权势状态UI组件 (PowerStatusIndicator.gd)
# 显示主子的名称、权势等级、特殊行动数量以及警告图标

@onready var master_name_label: Label = %MasterNameLabel
@onready var power_level_label: Label = %PowerLevelLabel
@onready var action_count_label: Label = %ActionCountLabel
@onready var warning_icon: TextureRect = %WarningIcon

var current_master_uid: String = ""
var current_game_id: String = ""

# 初始化显示
func setup(master_uid: String, game_id: String) -> void:
	current_master_uid = master_uid
	current_game_id = game_id
	refresh()

# 刷新数据
func refresh() -> void:
	if current_master_uid == "" or current_game_id == "":
		visible = false
		return
	
	visible = true
	
	# 1. 获取主子基础信息
	var p_res = await SupabaseManager.db_get("/rest/v1/players?id=eq.%s&select=character_name,is_disgraced" % current_master_uid)
	if p_res["code"] != 200 or p_res["data"].is_empty():
		return
	
	var p_data = p_res["data"][0]
	master_name_label.text = "主子: " + p_data.get("character_name", "未知")
	
	# 2. 获取权势等级
	var power_influence = get_node_or_null("/root/PowerInfluence")
	var level = "medium"
	if power_influence:
		level = await power_influence.get_power_level(current_master_uid, current_game_id)
	else:
		# 如果不是 Autoload，尝试手动加载或从父节点获取
		# 这里假设 PowerInfluence 已被挂载为 Autoload
		pass
	
	# 3. 设置权势等级文本与颜色
	# 金/灰/红 对应 高/中/低
	match level:
		"high":
			power_level_label.text = "权势: 高 (金)"
			power_level_label.add_theme_color_override("font_color", Color.GOLD)
		"medium":
			power_level_label.text = "权势: 中 (灰)"
			power_level_label.add_theme_color_override("font_color", Color.GRAY)
		"low":
			power_level_label.text = "权势: 低 (红)"
			power_level_label.add_theme_color_override("font_color", Color.CRIMSON)
	
	# 4. 获取特殊行动数量
	var actions = []
	if power_influence:
		# 这里需要一个能获取特定主子权势下可用行动的方法，
		# 实际上 get_available_actions 是给丫鬟调用的。
		# 我们根据 level 手动计算数量。
		match level:
			"low": actions = ["传递口信", "情报收集（受限）"]
			"medium": actions = ["传递口信", "情报收集", "挂机监听（正常速率）"]
			"high": actions = ["传递口信", "情报收集", "挂机监听（双倍速率）", "代主子传话", "代主子要账", "代主子出席"]
	
	action_count_label.text = "解锁特殊行动: %d" % actions.size()
	
	# 5. 显示警告图标（若主子被元老厌弃）
	warning_icon.visible = p_data.get("is_disgraced", false)
