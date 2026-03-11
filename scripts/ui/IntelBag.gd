extends Control

# 情报背包脚本 (IntelBag.gd)
# 实现玩家持有的情报碎片列表展示、详情、出售及发布流言等功能

@onready var stamina_label = $TopBar/StaminaLabel
@onready var qi_shu_label  = $TopBar/QiShuLabel
@onready var fragment_list = $Middle/ScrollContainer/FragmentList
@onready var detail_popup  = $DetailPopup
@onready var detail_content = $DetailPopup/VBox/ContentLabel
@onready var detail_target  = $DetailPopup/VBox/TargetLabel
@onready var sell_popup    = $SellPopup
@onready var sell_silver_input = $SellPopup/VBox/PriceGrid/SilverInput
@onready var sell_qi_input     = $SellPopup/VBox/PriceGrid/QiInput
@onready var sell_buyer_list   = $SellPopup/VBox/BuyerList
@onready var toast_label       = $ToastLabel # 假设已添加

const FRAGMENT_ITEM_SCENE = preload("res://scenes/components/IntelFragmentItem.tscn")

var _current_fragments: Array = []
var _selected_fragment_id: String = ""

func _ready() -> void:
	# 信号连接
	PlayerState.stamina_changed.connect(_on_stamina_changed)
	PlayerState.qi_shu_changed.connect(_on_qi_shu_changed)
	$SellPopup.confirmed.connect(_on_sell_confirmed)
	
	# 导航按钮连接
	$TopBar/BackBtn.pressed.connect(_on_BackBtn_pressed)
	$TopBar/InboxBtn.pressed.connect(_on_InboxBtn_pressed)
	
	# 初始化界面
	_on_stamina_changed(PlayerState.stamina)
	_on_qi_shu_changed(PlayerState.qi_shu)
	
	# 加载情报
	refresh_bag()

# ---------------------------------------------------------
# 数据加载与刷新
# ---------------------------------------------------------

## 从 Supabase 加载当前玩家持有的所有有效情报碎片
func refresh_bag() -> void:
	# 清空当前列表
	for child in fragment_list.get_children():
		child.queue_free()
	
	# 构造查询参数
	# owner_uid=当前玩家, is_used=false, is_sold=false, expires_at > now()
	var now_iso = Time.get_datetime_string_from_system(false, true)
	var endpoint = "/rest/v1/intel_fragments?owner_uid=eq.%s&is_used=eq.false&is_sold=eq.false&expires_at=gt.%s&select=*" % [
		PlayerState.uid, now_iso
	]
	
	var res = await SupabaseManager.db_get(endpoint)
	if res["code"] == 200:
		_current_fragments = res["data"]
		_populate_list(_current_fragments)
	else:
		_show_toast("加载情报失败: " + str(res.get("error", "网络连接异常")))

func _populate_list(fragments: Array) -> void:
	if fragments.is_empty():
		_show_toast("当前没有有效的情报")
		return
		
	for frag in fragments:
		var item = FRAGMENT_ITEM_SCENE.instantiate()
		fragment_list.add_child(item)
		item.setup(frag)
		
		# 连接 item 信号
		item.detail_pressed.connect(_on_fragment_selected)
		item.sell_pressed.connect(_on_sell_pressed)
		item.rumor_pressed.connect(_on_rumor_pressed)

# ---------------------------------------------------------
# 交互逻辑
# ---------------------------------------------------------

## 选中情报碎片后显示详情弹窗
func _on_fragment_selected(fragment_id: String) -> void:
	var frag = _find_fragment(fragment_id)
	if frag.is_empty(): return
	
	detail_content.text = frag.get("content", "无内容")
	
	# 查询目标玩家名称 (这里假设 frag 有 about_player_id)
	var target_uid = frag.get("about_player_id", "")
	if target_uid != "":
		# 实际项目中应缓存玩家名，这里简化处理
		detail_target.text = "指向目标: " + target_uid # 暂时显示 UID
	else:
		detail_target.text = "指向目标: 无"
		
	detail_popup.popup_centered()

## 出售情报：显示出售弹窗
func _on_sell_pressed(fragment_id: String) -> void:
	var frag = _find_fragment(fragment_id)
	if frag.is_empty(): return
	
	_selected_fragment_id = fragment_id
	
	# 重置输入
	sell_silver_input.value = 0
	sell_qi_input.value = 0
	
	# 加载潜在买家列表 (除了自己以外的所有玩家)
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

func _on_sell_confirmed() -> void:
	var silver = int(sell_silver_input.value)
	var qi = int(sell_qi_input.value)
	
	# 验证价格：不能同时填两个，也不能都不填
	if (silver > 0 and qi > 0) or (silver == 0 and qi == 0):
		_show_toast("银两和气数只能填一个，且不能为0")
		return
		
	var buyer_idx = sell_buyer_list.selected
	if buyer_idx < 0:
		_show_toast("请先选择一个买家")
		return
		
	var buyer_uid = sell_buyer_list.get_item_metadata(buyer_idx)
	create_trade_offer(_selected_fragment_id, buyer_uid, silver, qi)

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
		# 成功后可选：刷新列表
		refresh_bag()
	else:
		_show_toast("交易创建失败: " + str(res.get("error", "网络异常")))

## 简单 Toast 提示逻辑
func _show_toast(message: String):
	if not toast_label: return
	toast_label.text = message
	toast_label.modulate.a = 1.0
	toast_label.show()
	
	# 简单的渐隐动画
	var tween = create_tween()
	tween.tween_property(toast_label, "modulate:a", 0.0, 3.0).set_delay(1.5)
	tween.tween_callback(toast_label.hide)

## 发布流言：跳转流言发布界面
func _on_rumor_pressed(fragment_id: String) -> void:
	# 跳转到流言发布场景并携带 fragment_id
	# 假设场景路径为 res://scenes/RumorPublish.tscn
	# 此处通过全局变量或 SceneTree 传递
	get_tree().root.set_meta("pending_rumor_fragment_id", fragment_id)
	get_tree().change_scene_to_file("res://scenes/RumorPublish.tscn")

# ---------------------------------------------------------
# UI 更新
# ---------------------------------------------------------

func _on_stamina_changed(val: int) -> void:
	stamina_label.text = "精力: %d/%d" % [val, PlayerState.stamina_max]

func _on_qi_shu_changed(val: int) -> void:
	qi_shu_label.text = "气数: %d" % val

# ---------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------

func _find_fragment(id: String) -> Dictionary:
	for f in _current_fragments:
		if f["id"] == id:
			return f
	return {}

# 底部按钮回调
func _on_go_listening_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/EavesdropHub.tscn")

func _on_go_market_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Market.tscn")

func _on_BackBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _on_InboxBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Inbox.tscn")
