extends Control

# 《大观园》管家系统 · 测试调试面板
# 实现资源调试、月例发放、批条行动、查账、投票、路线检测及事件触发

@onready var content_vbox = $MainLayout/LeftPanel/ScrollContainer/Content
@onready var log_text = $MainLayout/RightPanel/LogContainer/LogText
@onready var status_container = $MainLayout/RightPanel/StatusContainer

# 模拟数据
var public_silver: int = 1200
var private_silver: int = 50
var prestige: int = 75
var deficit_rate: float = 0.0
var internal_conflict: float = 0.0
var stamina: int = 6
var stamina_max: int = 6

# 路由进度
var route_virtuous = {
	"deficit_ok": true,
	"satisfaction_ok": false,
	"no_complaints": true
}
var route_schemer = {
	"family_ruin": false,
	"private_assets_ok": false,
	"assets_transferred": false
}

func _ready():
	_setup_ui()
	_log("调试面板已就绪", "SYSTEM")

func _on_BackBtn_pressed():
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _setup_ui():
	# 清空现有 UI
	for child in content_vbox.get_children():
		child.queue_free()
	
	_create_header("🔄 全局操作")
	_create_reset_button()
	
	_create_header("💎 资源调试区")
	_setup_resource_debug()
	
	_create_header("💰 月例发放区")
	_setup_allowance_area()
	
	_create_header("📜 批条行动区")
	_setup_action_area()
	
	_create_header("🔍 查账系统区")
	_setup_audit_area()
	
	_create_header("🗳️ 言官投票区")
	_setup_voting_area()
	
	_create_header("🌿 双路线状态区")
	_setup_route_area()
	
	_create_header("🏮 事件快速触发区")
	_setup_event_area()

func _create_header(title: String):
	var label = Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_vbox.add_child(label)
	
	var hs = HSeparator.new()
	content_vbox.add_child(hs)

func _log(msg: String, type: String = "INFO"):
	var time = Time.get_time_string_from_system()
	var color = "white"
	match type:
		"SYSTEM": color = "cyan"
		"RESOURCE": color = "green"
		"RISK": color = "yellow"
		"CRITICAL": color = "red"
		"ACTION": color = "magenta"
	
	log_text.append_text("[color=%s][%s] [%s] %s[/color]\n" % [color, time, type, msg])

# --- 资源调试区 ---

func _setup_resource_debug():
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	content_vbox.add_child(grid)
	
	_add_resource_row(grid, "公中银库", "public_silver", 50, 1200)
	_add_resource_row(grid, "精 力", "stamina", 1, 6)
	_add_resource_row(grid, "威 望", "prestige", 10, 75)
	_add_resource_row(grid, "亏空值", "deficit_rate", 20, 0)
	_add_resource_row(grid, "内耗值", "internal_conflict", 15, 0)
	_add_resource_row(grid, "私 产", "private_silver", 50, 0)

func _add_resource_row(parent: Control, label_text: String, var_name: String, delta: int, reset_val: float):
	var btn_plus = Button.new()
	btn_plus.text = "+%d %s" % [delta, label_text]
	btn_plus.pressed.connect(func(): _update_resource(var_name, delta))
	parent.add_child(btn_plus)
	
	var btn_minus = Button.new()
	btn_minus.text = "-%d %s" % [delta, label_text]
	btn_minus.pressed.connect(func(): _update_resource(var_name, -delta))
	parent.add_child(btn_minus)
	
	var btn_reset = Button.new()
	btn_reset.text = "重置%s(%s)" % [label_text, str(reset_val)]
	btn_reset.pressed.connect(func(): _update_resource(var_name, reset_val, true))
	parent.add_child(btn_reset)
	
	# 数值显示
	var val_label = Label.new()
	val_label.name = "Label_" + var_name
	val_label.text = "当前: %s" % str(get(var_name))
	parent.add_child(val_label)
	# 占位符
	parent.add_child(Control.new())
	parent.add_child(Control.new())

func _update_resource(var_name: String, delta: float, is_reset: bool = false):
	var old_val = get(var_name)
	var new_val = delta if is_reset else old_val + delta
	
	# 边界保护
	if var_name == "stamina":
		new_val = clamp(new_val, 0, stamina_max)
	elif var_name in ["deficit_rate", "internal_conflict"]:
		new_val = clamp(new_val, 0, 100)
	elif var_name in ["prestige"]:
		new_val = clamp(new_val, 0, 200)
	else:
		new_val = max(0, new_val)
	
	set(var_name, new_val)
	_log("%s 变更为 %s (原值: %s)" % [var_name, str(new_val), str(old_val)], "RESOURCE")
	_refresh_resource_labels()
	_refresh_action_buttons()
	_update_route_conditions()

func _refresh_resource_labels():
	for var_name in ["public_silver", "stamina", "prestige", "deficit_rate", "internal_conflict", "private_silver"]:
		var label = content_vbox.find_child("Label_" + var_name, true, false)
		if label:
			label.text = "当前: %s" % str(get(var_name))

# --- 占位方法 (后续实现) ---

func _create_reset_button():
	var btn = Button.new()
	btn.text = "🔄 重置全部数据"
	btn.pressed.connect(_on_reset_all)
	content_vbox.add_child(btn)

# --- 重置与确认 ---

func _on_reset_all():
	_show_confirm("是否确认重置全部数据？此操作不可逆。", func():
		public_silver = 1200
		private_silver = 50
		prestige = 75
		deficit_rate = 0.0
		internal_conflict = 0.0
		stamina = 6
		total_paid = 0
		total_withheld = 0
		deduction_count = 0
		assets_transferred = false
		for p in players: p.paid = false
		
		_log("🔄 全部数据已重置", "SYSTEM")
		_refresh_resource_labels()
		_refresh_allowance_info()
		_refresh_action_buttons()
		_update_route_conditions()
		_setup_ui() # 重新构建 UI 以清除状态标记
	)

func _show_confirm(msg: String, on_confirm: Callable):
	var dialog = ConfirmationDialog.new()
	dialog.title = "危险操作确认"
	dialog.dialog_text = msg
	dialog.confirmed.connect(on_confirm)
	add_child(dialog)
	dialog.popup_centered()


# --- 月例发放区 ---

var players = [
	{"name": "林黛玉", "role": "主子", "standard": 30, "paid": false},
	{"name": "薛宝钗", "role": "主子", "standard": 30, "paid": false},
	{"name": "晴雯", "role": "丫鬟", "standard": 10, "paid": false},
	{"name": "袭人", "role": "丫鬟", "standard": 12, "paid": false}
]

var total_paid = 0
var total_withheld = 0
var deduction_count = 0

func _setup_allowance_area():
	var vbox = VBoxContainer.new()
	vbox.name = "AllowanceVBox"
	content_vbox.add_child(vbox)
	
	var grid = GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 10)
	vbox.add_child(grid)
	
	# 表头
	for text in ["名称", "角色", "标准", "实际", "操作", "状态", ""]:
		var label = Label.new()
		label.text = text
		grid.add_child(label)
	
	for i in range(players.size()):
		var p = players[i]
		
		# 名称、角色、标准
		grid.add_child(_create_label(p.name))
		grid.add_child(_create_label(p.role))
		grid.add_child(_create_label(str(p.standard)))
		
		# 实际发放输入框
		var input = SpinBox.new()
		input.max_value = 500
		input.value = p.standard
		input.name = "Input_" + str(i)
		grid.add_child(input)
		
		# 操作按钮 (HBox)
		var btn_hbox = HBoxContainer.new()
		grid.add_child(btn_hbox)
		
		var btn_full = Button.new()
		btn_full.text = "足额"
		btn_full.pressed.connect(func(): _pay_allowance(i, 1.0))
		btn_hbox.add_child(btn_full)
		
		var btn_10 = Button.new()
		btn_10.text = "克扣10%"
		btn_10.pressed.connect(func(): _pay_allowance(i, 0.9))
		btn_hbox.add_child(btn_10)
		
		var btn_30 = Button.new()
		btn_30.text = "克扣30%"
		btn_30.pressed.connect(func(): _pay_allowance(i, 0.7))
		btn_hbox.add_child(btn_30)
		
		var btn_extra = Button.new()
		btn_extra.text = "额外赏赐"
		btn_extra.pressed.connect(func(): _pay_allowance(i, 1.5, true))
		btn_hbox.add_child(btn_extra)
		
		# 状态标记
		var status_label = Label.new()
		status_label.name = "Status_" + str(i)
		status_label.text = "待发"
		grid.add_child(status_label)
		
		# 占位
		grid.add_child(Control.new())

	# 底部信息
	var info_label = Label.new()
	info_label.name = "AllowanceInfo"
	info_label.text = "本旬已发总额: 0 / 应发总额: 82 | 截留总额: 0 | 已克扣人数: 0"
	vbox.add_child(info_label)
	
	var warning_label = Label.new()
	warning_label.name = "AllowanceWarning"
	warning_label.text = "⚠️ 告状风险已触发"
	warning_label.add_theme_color_override("font_color", Color.RED)
	warning_label.visible = false
	vbox.add_child(warning_label)

func _create_label(text: String) -> Label:
	var l = Label.new()
	l.text = text
	return l

func _pay_allowance(index: int, ratio: float, is_extra: bool = false):
	var p = players[index]
	if p.paid: return
	
	var amount = floor(p.standard * ratio)
	var withheld = p.standard - amount if ratio < 1.0 else 0
	
	# 更新数值
	total_paid += amount
	if withheld > 0:
		total_withheld += withheld
		deduction_count += 1
		private_silver += withheld
	
	if is_extra:
		deficit_rate += 2
		prestige += 15 # 假设好感度映射到威望或类似的全局反馈
		_log("向 %s 额外赏赐 %d (标准 %d) -> 亏空+2, 威望+15" % [p.name, amount, p.standard], "ACTION")
	else:
		_log("向 %s 发放 %d (标准 %d, 克扣 %d) -> 私产+%d" % [p.name, amount, p.standard, withheld, withheld], "ACTION")
	
	p.paid = true
	
	# 更新 UI
	var status_label = content_vbox.find_child("Status_" + str(index), true, false)
	if status_label:
		status_label.text = "✓已发"
		status_label.add_theme_color_override("font_color", Color.GREEN)
	
	_refresh_allowance_info()
	_refresh_resource_labels()

func _refresh_allowance_info():
	var info = content_vbox.find_child("AllowanceInfo", true, false)
	if info:
		info.text = "本旬已发总额: %d / 应发总额: 82 | 截留总额: %d | 已克扣人数: %d" % [total_paid, total_withheld, deduction_count]
	
	var warning = content_vbox.find_child("AllowanceWarning", true, false)
	if warning:
		warning.visible = (deduction_count >= 3)

# --- 批条行动区 ---

var actions = [
	{"name": "🛒 采办物资", "cost": 1, "target": "随机玩家"},
	{"name": "📋 差使分派", "cost": 1, "target": "选择玩家"},
	{"name": "🔍 搜检大观园", "cost": 2, "target": "5-10人随机"},
	{"name": "📜 预支批条", "cost": 1, "target": "选择玩家"},
	{"name": "🤫 平息流言", "cost": 2, "target": "选择流言"},
	{"name": "🔒 封锁消息", "cost": 3, "target": "选择情报"}
]

func _setup_action_area():
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	content_vbox.add_child(grid)
	
	for i in range(actions.size()):
		var act = actions[i]
		var panel = PanelContainer.new()
		grid.add_child(panel)
		
		var vbox = VBoxContainer.new()
		panel.add_child(vbox)
		
		var title = Label.new()
		title.text = "%s (消耗%d精力)" % [act.name, act.cost]
		vbox.add_child(title)
		
		var target_btn = OptionButton.new()
		target_btn.add_item("目标: " + act.target)
		vbox.add_child(target_btn)
		
		var exec_btn = Button.new()
		exec_btn.text = "执行"
		exec_btn.name = "ActionBtn_" + str(i)
		exec_btn.pressed.connect(func(): _execute_action(i))
		vbox.add_child(exec_btn)
		
		_update_action_button_state(i, exec_btn)

func _update_action_button_state(index: int, btn: Button):
	var act = actions[index]
	if stamina < act.cost:
		btn.disabled = true
		btn.tooltip_text = "精力不足，剩余 %d 点" % stamina
	else:
		btn.disabled = false
		btn.tooltip_text = ""

func _execute_action(index: int):
	var act = actions[index]
	if stamina >= act.cost:
		stamina -= act.cost
		_log("执行行动: %s (消耗 %d 精力) -> 成功" % [act.name, act.cost], "ACTION")
		_refresh_resource_labels()
		_refresh_action_buttons()
	else:
		_log("行动失败: %s (精力不足)" % act.name, "CRITICAL")

func _refresh_action_buttons():
	for i in range(actions.size()):
		var btn = content_vbox.find_child("ActionBtn_" + str(i), true, false)
		if btn:
			_update_action_button_state(i, btn)

# --- 查账系统区 ---

var audit_status = "idle" # idle, filed, investigating, concluded

func _setup_audit_area():
	var vbox = VBoxContainer.new()
	vbox.name = "AuditVBox"
	content_vbox.add_child(vbox)
	
	# 阶段一
	var s1_label = Label.new()
	s1_label.text = "阶段一（模拟举报）"
	vbox.add_child(s1_label)
	
	var btn_report = Button.new()
	btn_report.text = "🗂️ 模拟举报发起查账"
	btn_report.name = "AuditBtn_Report"
	btn_report.pressed.connect(_on_audit_report)
	vbox.add_child(btn_report)
	
	vbox.add_child(HSeparator.new())
	
	# 阶段二
	var s2_label = Label.new()
	s2_label.text = "阶段二（应对措施）"
	vbox.add_child(s2_label)
	
	var h2 = HBoxContainer.new()
	vbox.add_child(h2)
	
	var btn_destroy = Button.new()
	btn_destroy.text = "🔥 销毁证据 (-30两)"
	btn_destroy.name = "AuditBtn_Destroy"
	btn_destroy.pressed.connect(func(): _on_audit_action("销毁证据", 30))
	h2.add_child(btn_destroy)
	
	var btn_bribe = Button.new()
	btn_bribe.text = "🤝 贿赂证人 (-50两)"
	btn_bribe.name = "AuditBtn_Bribe"
	btn_bribe.pressed.connect(func(): _on_audit_action("贿赂证人", 50))
	h2.add_child(btn_bribe)
	
	var btn_counter = Button.new()
	btn_counter.text = "⚔️ 反咬举报人"
	btn_counter.name = "AuditBtn_Counter"
	btn_counter.pressed.connect(func(): _on_audit_action("反咬举报人", 0))
	h2.add_child(btn_counter)
	
	vbox.add_child(HSeparator.new())
	
	# 阶段三
	var s3_label = Label.new()
	s3_label.text = "阶段三（手动触发裁决）"
	vbox.add_child(s3_label)
	
	var h3 = HBoxContainer.new()
	vbox.add_child(h3)
	
	var btn_v1 = Button.new()
	btn_v1.text = "⚖️ 触发裁决：无罪"
	btn_v1.name = "AuditBtn_V1"
	btn_v1.pressed.connect(func(): _on_audit_verdict("无罪"))
	h3.add_child(btn_v1)
	
	var btn_v2 = Button.new()
	btn_v2.text = "⚖️ 触发裁决：降级"
	btn_v2.name = "AuditBtn_V2"
	btn_v2.pressed.connect(func(): _on_audit_verdict("降级"))
	h3.add_child(btn_v2)
	
	var btn_v3 = Button.new()
	btn_v3.text = "⚖️ 触发裁决：抄家"
	btn_v3.name = "AuditBtn_V3"
	btn_v3.pressed.connect(func(): _on_audit_verdict("抄家"))
	h3.add_child(btn_v3)
	
	_refresh_audit_ui()

func _on_audit_report():
	audit_status = "filed"
	_log("举报发起（原告：茗烟）-> 消耗举报者20气数，案件进入调查阶段", "ACTION")
	_refresh_audit_ui()

func _on_audit_action(action_name: String, cost: int):
	if private_silver >= cost:
		private_silver -= cost
		_log("执行应对: %s -> 成功 (消耗私产 %d)" % [action_name, cost], "ACTION")
		_refresh_resource_labels()
	else:
		_log("执行应对失败: %s (私产不足)" % action_name, "CRITICAL")

func _on_audit_verdict(verdict: String):
	_log("收到裁决结果: %s" % verdict, "CRITICAL")
	match verdict:
		"无罪":
			_log("判定无罪: 举报者-20气数，案件关闭", "SYSTEM")
		"降级":
			prestige = 0
			private_silver = 0
			_log("判定降级: 威望归零，私产没收", "CRITICAL")
		"抄家":
			internal_conflict = 100
			_log("判定抄家: 内耗值爆表，触发全局抄家事件", "CRITICAL")
			_trigger_global_event("抄家")
	
	audit_status = "idle"
	_refresh_audit_ui()
	_refresh_resource_labels()

func _refresh_audit_ui():
	var btn_report = content_vbox.find_child("AuditBtn_Report", true, false)
	if btn_report: btn_report.disabled = (audit_status != "idle")
	
	var btn_destroy = content_vbox.find_child("AuditBtn_Destroy", true, false)
	if btn_destroy: btn_destroy.disabled = (audit_status != "filed")
	
	var btn_bribe = content_vbox.find_child("AuditBtn_Bribe", true, false)
	if btn_bribe: btn_bribe.disabled = (audit_status != "filed")
	
	var btn_counter = content_vbox.find_child("AuditBtn_Counter", true, false)
	if btn_counter: btn_counter.disabled = (audit_status != "filed")
	
	var btn_v1 = content_vbox.find_child("AuditBtn_V1", true, false)
	if btn_v1: btn_v1.disabled = (audit_status != "filed")
	
	var btn_v2 = content_vbox.find_child("AuditBtn_V2", true, false)
	if btn_v2: btn_v2.disabled = (audit_status != "filed")
	
	var btn_v3 = content_vbox.find_child("AuditBtn_V3", true, false)
	if btn_v3: btn_v3.disabled = (audit_status != "filed")

func _trigger_global_event(event_name: String):
	# TODO: 弹出全局警告窗
	_log("🚨 全局事件触发: %s" % event_name, "CRITICAL")

# --- 言官投票区 ---

var fair_votes = 0
var unfair_votes = 0
var is_voting = false

func _setup_voting_area():
	var vbox = VBoxContainer.new()
	vbox.name = "VotingVBox"
	content_vbox.add_child(vbox)
	
	var btn_trigger = Button.new()
	btn_trigger.text = "🗳️ 触发投票窗口 (即时)"
	btn_trigger.name = "VotingBtn_Trigger"
	btn_trigger.pressed.connect(_on_trigger_vote)
	vbox.add_child(btn_trigger)
	
	var grid = GridContainer.new()
	grid.columns = 3
	vbox.add_child(grid)
	
	var btn_f1 = Button.new()
	btn_f1.text = "+1 公正票"
	btn_f1.pressed.connect(func(): _add_vote("fair", 1))
	grid.add_child(btn_f1)
	
	var btn_f5 = Button.new()
	btn_f5.text = "+5 公正票"
	btn_f5.pressed.connect(func(): _add_vote("fair", 5))
	grid.add_child(btn_f5)
	
	var label_fair = Label.new()
	label_fair.name = "Label_FairVotes"
	label_fair.text = "当前公正: 0 票"
	grid.add_child(label_fair)
	
	var btn_u1 = Button.new()
	btn_u1.text = "+1 不公票"
	btn_u1.pressed.connect(func(): _add_vote("unfair", 1))
	grid.add_child(btn_u1)
	
	var btn_u5 = Button.new()
	btn_u5.text = "+5 不公票"
	btn_u5.pressed.connect(func(): _add_vote("unfair", 5))
	grid.add_child(btn_u5)
	
	var label_unfair = Label.new()
	label_unfair.name = "Label_UnfairVotes"
	label_unfair.text = "当前不公: 0 票"
	grid.add_child(label_unfair)
	
	var btn_settle = Button.new()
	btn_settle.text = "立即结算投票"
	btn_settle.pressed.connect(_on_settle_vote)
	vbox.add_child(btn_settle)
	
	var ratio_label = Label.new()
	ratio_label.name = "Label_VoteRatio"
	ratio_label.text = "实时不公比例: 0%"
	vbox.add_child(ratio_label)
	
	var warning_y = Label.new()
	warning_y.name = "VoteWarning_Y"
	warning_y.text = "⚠️ 威望-15，决策可被撤销"
	warning_y.add_theme_color_override("font_color", Color.YELLOW)
	warning_y.visible = false
	vbox.add_child(warning_y)
	
	var warning_r = Label.new()
	warning_r.name = "VoteWarning_R"
	warning_r.text = "🚨 元老已收到罢免申请"
	warning_r.add_theme_color_override("font_color", Color.RED)
	warning_r.visible = false
	vbox.add_child(warning_r)

func _on_trigger_vote():
	is_voting = true
	fair_votes = 0
	unfair_votes = 0
	_log("投票窗口已激活", "SYSTEM")
	_refresh_vote_ui()

func _add_vote(type: String, count: int):
	if !is_voting: return
	if type == "fair":
		fair_votes += count
	else:
		unfair_votes += count
	_refresh_vote_ui()

func _on_settle_vote():
	if !is_voting: return
	var total = fair_votes + unfair_votes
	var ratio = (float(unfair_votes) / total * 100.0) if total > 0 else 0.0
	_log("投票结算: 总票数 %d, 不公比例 %.1f%%" % [total, ratio], "SYSTEM")
	is_voting = false
	_refresh_vote_ui()

func _refresh_vote_ui():
	var total = fair_votes + unfair_votes
	var ratio = (float(unfair_votes) / total * 100.0) if total > 0 else 0.0
	
	var lf = content_vbox.find_child("Label_FairVotes", true, false)
	if lf: lf.text = "当前公正: %d 票" % fair_votes
	
	var lu = content_vbox.find_child("Label_UnfairVotes", true, false)
	if lu: lu.text = "当前不公: %d 票" % unfair_votes
	
	var lr = content_vbox.find_child("Label_VoteRatio", true, false)
	if lr: lr.text = "实时不公比例: %.1f%%" % ratio
	
	var wy = content_vbox.find_child("VoteWarning_Y", true, false)
	if wy: wy.visible = (ratio >= 20)
	
	var wr = content_vbox.find_child("VoteWarning_R", true, false)
	if wr: wr.visible = (ratio >= 40)

# --- 双路线状态区 ---

var assets_transferred = false

func _setup_route_area():
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	content_vbox.add_child(grid)
	
	# 贤能管家
	var v_virtuous = VBoxContainer.new()
	grid.add_child(v_virtuous)
	
	v_virtuous.add_child(_create_label("🌿 贤能管家路线"))
	v_virtuous.add_child(_create_status_label("RouteV_Deficit", "家族亏空 ≤ 15%"))
	v_virtuous.add_child(_create_status_label("RouteV_Satisfaction", "平均满意度 ≥ 70%"))
	v_virtuous.add_child(_create_status_label("RouteV_Complaints", "无告状记录"))
	
	var btn_v_end = Button.new()
	btn_v_end.text = "模拟达成贤能结局"
	btn_v_end.pressed.connect(func(): _log("模拟达成: 贤能管家结局", "SYSTEM"))
	v_virtuous.add_child(btn_v_end)
	
	# 末世枭雄
	var v_schemer = VBoxContainer.new()
	grid.add_child(v_schemer)
	
	v_schemer.add_child(_create_label("🐍 末世枭雄路线"))
	v_schemer.add_child(_create_status_label("RouteS_Ruin", "家族覆灭 (内耗100%)"))
	v_schemer.add_child(_create_status_label("RouteS_Assets", "私产 ≥ 500两"))
	v_schemer.add_child(_create_status_label("RouteS_Transfer", "抄家前完成资产转移"))
	
	var h_btns = HBoxContainer.new()
	v_schemer.add_child(h_btns)
	
	var btn_s_end = Button.new()
	btn_s_end.text = "模拟达成枭雄结局"
	btn_s_end.pressed.connect(func(): _log("模拟达成: 末世枭雄结局", "SYSTEM"))
	h_btns.add_child(btn_s_end)
	
	var btn_transfer = Button.new()
	btn_transfer.text = "模拟资产转移"
	btn_transfer.pressed.connect(_on_transfer_assets)
	h_btns.add_child(btn_transfer)
	
	_update_route_conditions()

func _create_status_label(node_name: String, text: String) -> Label:
	var l = Label.new()
	l.name = node_name
	l.text = "❌ " + text
	return l

func _on_transfer_assets():
	assets_transferred = true
	_log("资产转移成功: 私产已安全保存", "ACTION")
	_update_route_conditions()

func _update_route_conditions():
	# 贤能管家检测
	var v_deficit = content_vbox.find_child("RouteV_Deficit", true, false)
	if v_deficit:
		var ok = deficit_rate <= 15
		v_deficit.text = "%s 家族亏空 ≤ 15%% (当前: %.1f%%)" % [("✅" if ok else "❌"), deficit_rate]
		v_deficit.add_theme_color_override("font_color", Color.GREEN if ok else Color.WHITE)
		
	var v_sat = content_vbox.find_child("RouteV_Satisfaction", true, false)
	if v_sat:
		var ok = prestige >= 140 # 模拟满意度
		v_sat.text = "%s 平均满意度 ≥ 70%% (当前: %.1f%%)" % [("✅" if ok else "❌"), (float(prestige) / 2.0)]
		v_sat.add_theme_color_override("font_color", Color.GREEN if ok else Color.WHITE)
		
	var v_comp = content_vbox.find_child("RouteV_Complaints", true, false)
	if v_comp:
		var ok = deduction_count == 0
		v_comp.text = "%s 无告状记录 (当前: %d件)" % [("✅" if ok else "❌"), deduction_count]
		v_comp.add_theme_color_override("font_color", Color.GREEN if ok else Color.WHITE)
		
	# 末世枭雄检测
	var s_ruin = content_vbox.find_child("RouteS_Ruin", true, false)
	if s_ruin:
		var ok = internal_conflict >= 100
		s_ruin.text = "%s 家族覆灭 (内耗100%%)" % ("✅" if ok else "❌")
		s_ruin.add_theme_color_override("font_color", Color.GREEN if ok else Color.WHITE)
		
	var s_assets = content_vbox.find_child("RouteS_Assets", true, false)
	if s_assets:
		var ok = private_silver >= 500
		s_assets.text = "%s 私产 ≥ 500两 (当前: %d两)" % [("✅" if ok else "❌"), private_silver]
		s_assets.add_theme_color_override("font_color", Color.GREEN if ok else Color.WHITE)
		
	var s_trans = content_vbox.find_child("RouteS_Transfer", true, false)
	if s_trans:
		s_trans.text = "%s 抄家前完成资产转移" % ("✅" if assets_transferred else "❌")
		s_trans.add_theme_color_override("font_color", Color.GREEN if assets_transferred else Color.WHITE)

# --- 事件快速触发区 ---

func _setup_event_area():
	var flow = FlowContainer.new()
	content_vbox.add_child(flow)
	
	var events = [
		{"name": "🏮 触发：元妃省亲", "fn": _on_event_yuanfei},
		{"name": "ⰰ️ 触发：大出殡", "fn": _on_event_funeral},
		{"name": "🔥 触发：抄检大观园", "fn": _on_event_raid},
		{"name": "🔍 触发：贾政大检查", "fn": _on_event_check},
		{"name": "👵 触发：刘姥姥进大观园", "fn": _on_event_liulaolao}
	]
	
	for e in events:
		var btn = Button.new()
		btn.text = e.name
		btn.pressed.connect(e.fn)
		flow.add_child(btn)

func _on_event_yuanfei():
	deficit_rate += 25
	_log("触发：元妃省亲 -> 亏空值+25，所有精力消耗翻倍提示", "CRITICAL")
	_refresh_resource_labels()
	_update_route_conditions()

func _on_event_funeral():
	_log("触发：大出殡 -> 诗社暂停，月例暂停发放", "CRITICAL")

func _on_event_raid():
	internal_conflict = 85
	_log("触发：抄检大观园 -> 内耗值飙升至85%，全员背包曝光提示", "CRITICAL")
	_refresh_resource_labels()
	_update_route_conditions()

func _on_event_check():
	_log("触发：贾政大检查 -> 24小时违禁品转移窗口开启", "RISK")

func _on_event_liulaolao():
	public_silver -= 50
	internal_conflict = max(0, internal_conflict - 8)
	_log("触发：刘姥姥进大观园 -> 消耗公中银50，内耗值-8", "RESOURCE")
	_refresh_resource_labels()
	_update_route_conditions()
