extends Control

# 情报背包脚本 (IntelBag.gd)
# 实现玩家持有的情报碎片列表展示、详情、出售及发布流言等功能

@onready var stamina_label = $TopBar/StaminaLabel
@onready var qi_shu_label  = $TopBar/QiShuLabel
@onready var fragment_list = $Middle/ScrollContainer/FragmentList
@onready var detail_popup  = $DetailPopup
@onready var detail_content = $DetailPopup/VBox/ContentLabel
@onready var detail_target  = $DetailPopup/VBox/TargetLabel
@onready var detail_type    = $DetailPopup/VBox/TypeLabel
@onready var detail_value   = $DetailPopup/VBox/ValueLabel
@onready var sell_popup    = $SellPopup
@onready var sell_silver_input = $SellPopup/VBox/PriceGrid/SilverInput
@onready var sell_qi_input     = $SellPopup/VBox/PriceGrid/QiInput
@onready var sell_buyer_list   = $SellPopup/VBox/BuyerList
@onready var toast_label       = $ToastLabel
@onready var block_btn: Button = get_node_or_null("DetailPopup/VBox/BlockBtn")

# 筛选相关
@onready var filter_type_option = $Middle/FilterBar/TypeOption
@onready var filter_scene_option = $Middle/FilterBar/SceneOption
@onready var filter_value_option = $Middle/FilterBar/ValueOption
@onready var sort_option = $Middle/FilterBar/SortOption
@onready var clear_filter_btn = $Middle/FilterBar/ClearFilterBtn

const FRAGMENT_ITEM_SCENE = preload("res://scenes/components/IntelFragmentItem.tscn")

var _current_fragments: Array = []
var _filtered_fragments: Array = []
var _selected_fragment_id: String = ""
var _current_filter: Dictionary = {
	"type": "all",
	"scene": "all",
	"value": "all",
	"sort": "time_desc"
}

func _ready() -> void:
	_setup_signals()
	_setup_filters()
	_setup_stamina_display()
	refresh_bag()

func _setup_signals():
	# 导航按钮
	$TopBar/BackBtn.pressed.connect(_on_BackBtn_pressed)
	$TopBar/InboxBtn.pressed.connect(_on_InboxBtn_pressed)
	
	# 底部按钮
	$BottomBar/ListenBtn.pressed.connect(_on_go_listening_pressed)
	$BottomBar/MarketBtn.pressed.connect(_on_go_market_pressed)
	
	# 弹窗信号
	if sell_popup.has_signal("confirmed"):
		sell_popup.confirmed.connect(_on_sell_confirmed)
	
	# 封锁按钮
	if block_btn:
		block_btn.pressed.connect(_on_block_btn_pressed)
	
	# 详情弹窗关闭时清空选择
	detail_popup.canceled.connect(_on_detail_closed)

func _setup_filters():
	# 类型筛选
	filter_type_option.clear()
	filter_type_option.add_item("全部类型", "all")
	filter_type_option.add_item("账目泄露", "account_leak")
	filter_type_option.add_item("私密行动", "private_action")
	filter_type_option.add_item("馈赠记录", "gift_record")
	filter_type_option.add_item("访客信息", "visitor_info")
	filter_type_option.add_item("长辈青睐", "elder_favor")
	filter_type_option.item_selected.connect(_on_filter_changed)
	
	# 场景筛选
	filter_scene_option.clear()
	filter_scene_option.add_item("全部场景", "all")
	filter_scene_option.add_item("怡红院", "yi_hong_yuan")
	filter_scene_option.add_item("后账房", "treasury_back")
	filter_scene_option.add_item("蜂腰桥", "bridge")
	filter_scene_option.add_item("大门", "gate")
	filter_scene_option.add_item("贾母处", "elder_room")
	filter_scene_option.item_selected.connect(_on_filter_changed)
	
	# 价值筛选
	filter_value_option.clear()
	filter_value_option.add_item("全部价值", "all")
	filter_value_option.add_item("★ (低)", "1")
	filter_value_option.add_item("★★ (中)", "2")
	filter_value_option.add_item("★★★ (较高)", "3")
	filter_value_option.add_item("★★★★ (高)", "4")
	filter_value_option.add_item("★★★★★ (极高)", "5")
	filter_value_option.item_selected.connect(_on_filter_changed)
	
	# 排序选项
	sort_option.clear()
	sort_option.add_item("按时间 (新→旧)", "time_desc")
	sort_option.add_item("按时间 (旧→新)", "time_asc")
	sort_option.add_item("按价值 (高→低)", "value_desc")
	sort_option.add_item("按价值 (低→高)", "value_asc")
	sort_option.item_selected.connect(_on_filter_changed)
	
	# 清除筛选
	clear_filter_btn.pressed.connect(_on_clear_filter_pressed)

func _setup_stamina_display():
	PlayerState.stamina_changed.connect(_on_stamina_changed)
	PlayerState.qi_shu_changed.connect(_on_qi_shu_changed)
	_on_stamina_changed(PlayerState.stamina)
	_on_qi_shu_changed(PlayerState.qi_shu)

# ---------------------------------------------------------
# 数据加载与筛选
# ---------------------------------------------------------

## 从 Supabase 加载当前玩家持有的所有有效情报碎片
func refresh_bag() -> void:
	for child in fragment_list.get_children():
		child.queue_free()
	
	_current_fragments.clear()
	_filtered_fragments.clear()

	var now_iso = Time.get_datetime_string_from_system(false, true)
	var endpoint = "/rest/v1/intel_fragments?owner_uid=eq.%s&is_used=eq.false&is_sold=eq.false&expires_at=gt.%s&select=*" % [
		PlayerState.uid, now_iso
	]

	var res = await SupabaseManager.db_get(endpoint)
	if res["code"] == 200:
		_current_fragments = res["data"]
		_apply_filters()
	else:
		_show_toast("加载情报失败：" + str(res.get("error", "网络连接异常")))

func _apply_filters():
	_filtered_fragments = _current_fragments.duplicate()
	
	# 类型筛选
	if _current_filter["type"] != "all":
		_filtered_fragments = _filtered_fragments.filter(func(f): 
			return f.get("intel_type", "") == _current_filter["type"]
		)
	
	# 场景筛选
	if _current_filter["scene"] != "all":
		_filtered_fragments = _filtered_fragments.filter(func(f): 
			return f.get("scene_key", f.get("scene", "")) == _current_filter["scene"]
		)
	
	# 价值筛选
	if _current_filter["value"] != "all":
		var target_value = int(_current_filter["value"])
		_filtered_fragments = _filtered_fragments.filter(func(f): 
			return f.get("value_level", 1) >= target_value
		)
	
	# 排序
	_sort_fragments()
	
	_populate_list(_filtered_fragments)

func _sort_fragments():
	match _current_filter["sort"]:
		"time_desc":
			_filtered_fragments.sort_custom(func(a, b): 
				return a.get("obtained_at", "") > b.get("obtained_at", "")
			)
		"time_asc":
			_filtered_fragments.sort_custom(func(a, b): 
				return a.get("obtained_at", "") < b.get("obtained_at", "")
			)
		"value_desc":
			_filtered_fragments.sort_custom(func(a, b): 
				return a.get("value_level", 1) > b.get("value_level", 1)
			)
		"value_asc":
			_filtered_fragments.sort_custom(func(a, b): 
				return a.get("value_level", 1) < b.get("value_level", 1)
			)

func _populate_list(fragments: Array) -> void:
	if fragments.is_empty():
		_show_toast("当前没有符合筛选条件的情报")
		return

	for frag in fragments:
		var item = FRAGMENT_ITEM_SCENE.instantiate()
		fragment_list.add_child(item)
		item.setup(frag)

		# 连接 item 信号
		item.detail_pressed.connect(_on_fragment_selected)
		item.sell_pressed.connect(_on_sell_pressed)
		item.rumor_pressed.connect(_on_rumor_pressed)
		item.expired.connect(_on_fragment_expired)

# ---------------------------------------------------------
# 交互逻辑
# ---------------------------------------------------------

func _on_filter_changed(_idx):
	_current_filter["type"] = filter_type_option.get_item_metadata(filter_type_option.selected)
	_current_filter["scene"] = filter_scene_option.get_item_metadata(filter_scene_option.selected)
	_current_filter["value"] = filter_value_option.get_item_metadata(filter_value_option.selected)
	_current_filter["sort"] = sort_option.get_item_metadata(sort_option.selected)
	_apply_filters()

func _on_clear_filter_pressed():
	filter_type_option.selected = 0
	filter_scene_option.selected = 0
	filter_value_option.selected = 0
	sort_option.selected = 0
	_current_filter = {
		"type": "all",
		"scene": "all",
		"value": "all",
		"sort": "time_desc"
	}
	_apply_filters()

## 选中情报碎片后显示详情弹窗
func _on_fragment_selected(fragment_id: String) -> void:
	var frag = _find_fragment(fragment_id)
	if frag.is_empty():
		return

	_selected_fragment_id = fragment_id

	detail_content.text = frag.get("content", "无内容")
	
	# 类型
	var type_name = frag.get("intel_type", "unknown")
	detail_type.text = "类型：" + _localize_intel_type(type_name)
	
	# 价值
	var value_level = frag.get("value_level", 1)
	detail_value.text = "价值：" + "★".repeat(value_level) + "☆".repeat(5 - value_level)

	# 目标玩家
	var target_uid = frag.get("source_uid", frag.get("about_player_id", ""))
	if target_uid != "":
		var p_res = await SupabaseManager.db_get("/rest/v1/players?uid=eq.%s&select=character_name" % target_uid)
		if p_res["code"] == 200 and not p_res["data"].is_empty():
			detail_target.text = "相关人物：" + p_res["data"][0]["character_name"]
		else:
			detail_target.text = "相关人物：未知"
	else:
		detail_target.text = "相关人物：无"

	if block_btn:
		block_btn.visible = (PlayerState.role_class == "steward")
	
	detail_popup.popup_centered()

func _on_detail_closed():
	_selected_fragment_id = ""

func _localize_intel_type(type: String) -> String:
	match type:
		"account_leak": return "账目泄露"
		"private_action": return "私密行动"
		"gift_record": return "馈赠记录"
		"visitor_info": return "访客信息"
		"elder_favor": return "长辈青睐"
		_: return "未知"

## 出售情报：显示出售弹窗
func _on_sell_pressed(fragment_id: String) -> void:
	var frag = _find_fragment(fragment_id)
	if frag.is_empty():
		return

	_selected_fragment_id = fragment_id

	sell_silver_input.value = 0
	sell_qi_input.value = 0

	_load_buyer_list()

	sell_popup.popup_centered()

func _load_buyer_list() -> void:
	sell_buyer_list.clear()
	var endpoint = "/rest/v1/players?id=neq.%s&select=id,character_name" % PlayerState.uid
	var res = await SupabaseManager.db_get(endpoint)
	if res["code"] == 200:
		for p in res["data"]:
			sell_buyer_list.add_item(p["character_name"], 0)
			sell_buyer_list.set_item_metadata(sell_buyer_list.get_item_count() - 1, p["id"])
	else:
		_show_toast("加载买家列表失败")

func _on_sell_confirmed() -> void:
	var silver = int(sell_silver_input.value)
	var qi = int(sell_qi_input.value)

	if (silver > 0 and qi > 0) or (silver == 0 and qi == 0):
		_show_toast("银两和气数只能填一个，且不能为 0")
		return

	var buyer_idx = sell_buyer_list.selected
	if buyer_idx < 0:
		_show_toast("请先选择一个买家")
		return

	var buyer_uid = sell_buyer_list.get_item_metadata(buyer_idx)
	await create_trade_offer(_selected_fragment_id, buyer_uid, silver, qi)

func _on_block_btn_pressed() -> void:
	if _selected_fragment_id == "":
		_show_toast("请先选择一条情报")
		return
	await _block_intel(_selected_fragment_id)

func _block_intel(fragment_id: String) -> void:
	var res = await SupabaseManager.db_rpc("steward_block_intel", {
		"p_intel_id": fragment_id
	})
	
	var ok: bool = int(res.get("code", 0)) == 200
	if ok:
		var data = res.get("data")
		if data is Dictionary and data.has("success") and data["success"] == false:
			ok = false

	if ok:
		_show_toast("已封锁该条情报，12 小时内他人无法查看")
		detail_popup.hide()
		refresh_bag()
	else:
		var err = str(res.get("error", res.get("data", {}).get("error", "未知错误")))
		_show_toast("封锁失败：" + err)

## 创建交易请求
func create_trade_offer(fragment_id: String, buyer_uid: String, silver: int, qi: int) -> void:
	var trade_data = {
		"game_id": GameState.current_game_id,
		"seller_uid": PlayerState.uid,
		"buyer_uid": buyer_uid,
		"fragment_id": fragment_id,
		"price_silver": silver,
		"price_qi": qi,
		"status": "pending"
	}

	var res = await SupabaseManager.db_insert("intel_trades", trade_data)
	if res["code"] == 201:
		_show_toast("交易请求已发送，等待对方确认")
		detail_popup.hide()
		refresh_bag()
	else:
		_show_toast("交易创建失败：" + str(res.get("error", "网络异常")))

## 发布流言：跳转流言发布界面
func _on_rumor_pressed(fragment_id: String) -> void:
	get_tree().root.set_meta("pending_rumor_fragment_id", fragment_id)
	get_tree().change_scene_to_file("res://scenes/RumorPublish.tscn")

func _on_fragment_expired(fragment_id: String):
	# 从列表中移除过期情报
	_current_fragments = _current_fragments.filter(func(f): return f["id"] != fragment_id)
	_filtered_fragments = _filtered_fragments.filter(func(f): return f["id"] != fragment_id)
	_show_toast("一条情报已过期")

# ---------------------------------------------------------
# UI 更新
# ---------------------------------------------------------

func _on_stamina_changed(val: int) -> void:
	stamina_label.text = "精力：%d/%d" % [val, PlayerState.stamina_max]

func _on_qi_shu_changed(val: int) -> void:
	qi_shu_label.text = "气数：%d" % val

# ---------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------

func _find_fragment(id: String) -> Dictionary:
	for f in _current_fragments:
		if f["id"] == id:
			return f
	return {}

func _show_toast(message: String):
	if not toast_label:
		print(message)
		return
	
	toast_label.text = message
	toast_label.modulate.a = 1.0
	toast_label.show()

	var tween = create_tween()
	tween.tween_property(toast_label, "modulate:a", 0.0, 3.0).set_delay(1.5)
	tween.tween_callback(toast_label.hide)

# 底部按钮回调
func _on_go_listening_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/EavesdropScene.tscn")

func _on_go_market_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Market.tscn")

func _on_BackBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _on_InboxBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Inbox.tscn")
