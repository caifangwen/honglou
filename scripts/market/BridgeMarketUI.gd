extends Control

# BridgeMarketUI.gd
# 蜂腰桥集市界面核心逻辑

@onready var tab_container = $VBoxMain/TabContainer
@onready var listings_grid = $VBoxMain/TabContainer/Browse/ScrollContainer/GridContainer
@onready var my_listings_list = $VBoxMain/TabContainer/MySales/ScrollContainer/VBoxContainer
@onready var type_filter = $VBoxMain/TabContainer/Browse/HBoxContainer/TypeFilter
@onready var sort_order = $VBoxMain/TabContainer/Browse/HBoxContainer/SortOrder
@onready var silver_label = $VBoxMain/TabContainer/Browse/HBoxContainer/SilverLabel
@onready var qi_label = $VBoxMain/TabContainer/Browse/HBoxContainer/QiLabel
@onready var back_btn = $VBoxMain/TopBar/BackBtn

@onready var confirm_panel = $PurchaseConfirmPanel
@onready var intel_type_label = $PurchaseConfirmPanel/VBox/IntelTypeLabel
@onready var price_label = $PurchaseConfirmPanel/VBox/PriceLabel
@onready var confirm_buy_btn = $PurchaseConfirmPanel/VBox/HBox/ConfirmBtn
@onready var cancel_buy_btn = $PurchaseConfirmPanel/VBox/HBox/CancelBtn

const LISTING_CARD_SCENE = preload("res://scenes/market/ListingCard.tscn")
const MARKET_LOGIC = preload("res://scripts/market/BridgeMarket.gd")

var _market: Node
var _selected_trade_id: String = ""
var _all_listings: Array = []

func _ready():
	_market = MARKET_LOGIC.new()
	add_child(_market)
	
	_refresh_currency()
	_load_listings()
	
	# 信号连接
	PlayerState.silver_changed.connect(func(_v): _refresh_currency())
	PlayerState.qi_shu_changed.connect(func(_v): _refresh_currency())
	
	type_filter.item_selected.connect(_on_filter_changed)
	sort_order.item_selected.connect(_on_filter_changed)
	
	back_btn.pressed.connect(_on_back_pressed)
	
	confirm_buy_btn.pressed.connect(_on_confirm_purchase)
	cancel_buy_btn.pressed.connect(func(): confirm_panel.hide())
	
	# 初始化筛选器
	_setup_filters()
	_load_my_listings()

func _refresh_currency():
	silver_label.text = "银两: %d" % PlayerState.silver
	qi_label.text = "气数: %d" % PlayerState.qi_shu

func _setup_filters():
	type_filter.clear()
	type_filter.add_item("所有类型")
	type_filter.add_item("账目漏洞", 1)
	type_filter.add_item("私相授受", 2)
	type_filter.add_item("行踪诡秘", 3)
	
	sort_order.clear()
	sort_order.add_item("最新挂单")
	sort_order.add_item("价格从低到高")
	sort_order.add_item("价格从高到低")

func _load_listings():
	# 只有丫鬟可以进入
	if not _market.can_enter():
		# 提示无权进入
		return
		
	_all_listings = await _market.get_market_listings(PlayerState.current_game_id)
	_apply_filters()

func _apply_filters():
	# 清空
	for child in listings_grid.get_children():
		child.queue_free()
	
	var filtered = _all_listings.duplicate()
	# TODO: 真正实现筛选和排序逻辑
	
	for data in filtered:
		var card = LISTING_CARD_SCENE.instantiate()
		listings_grid.add_child(card)
		card.setup(data)
		card.purchase_pressed.connect(_on_purchase_pressed)
		card.preview_pressed.connect(_on_preview_pressed)

func _on_purchase_pressed(trade_id: String):
	_selected_trade_id = trade_id
	# 查找选中项的数据
	for item in _all_listings:
		if item["trade_id"] == trade_id:
			intel_type_label.text = "情报类型: " + _localize_type(item["intel_type"])
			if item["price_silver"] > 0:
				price_label.text = "价格: %d 银两" % item["price_silver"]
			else:
				price_label.text = "价格: %d 气数" % item["price_qi"]
			break
	
	confirm_panel.show()

func _on_confirm_purchase():
	var res = await _market.purchase_intel(_selected_trade_id, PlayerState.uid)
	if res["success"]:
		confirm_panel.hide()
		_load_listings() # 刷新列表
		_show_fragment_content(res["fragment"])
	else:
		# 弹出错误提示
		_show_error(res.get("error", "购买失败"))

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _on_preview_pressed(_trade_id: String, scene_name: String):
	# 只显示来源场景，不显示具体内容
	# 此处可以用弹窗显示简单的预览信息
	pass

func _load_my_listings():
	# 获取当前玩家挂出的交易
	var endpoint = "/rest/v1/intel_trades?seller_uid=eq.%s&status=eq.pending&select=*,intel_fragments(intel_type,value_level)" % PlayerState.uid
	var res = await SupabaseManager.db_get(endpoint)
	
	# 清空
	for child in my_listings_list.get_children():
		child.queue_free()
	
	if res["code"] == 200:
		for trade in res["data"]:
			var item = _create_my_listing_item(trade)
			my_listings_list.add_child(item)

func _create_my_listing_item(trade: Dictionary) -> Control:
	var hbox = HBoxContainer.new()
	var frag = trade.get("intel_fragments", {})
	if frag is Array: frag = frag[0] if not frag.is_empty() else {}
	
	var name_label = Label.new()
	name_label.text = "[%s]" % _localize_type(frag.get("intel_type", "unknown"))
	hbox.add_child(name_label)
	
	var price_label = Label.new()
	if trade["price_silver"] > 0:
		price_label.text = "%d 银两" % trade["price_silver"]
	else:
		price_label.text = "%d 气数" % trade["price_qi"]
	hbox.add_child(price_label)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消挂单"
	cancel_btn.pressed.connect(func(): 
		if await _market.cancel_listing(trade["id"]):
			_load_my_listings()
			_load_listings()
	)
	hbox.add_child(cancel_btn)
	
	return hbox

func _on_list_new_intel():
	# 逻辑：打开一个 IntelBag 的变体或弹窗，让玩家选择要挂单的碎片
	pass

func _on_filter_changed(_index):
	_apply_filters()

func _localize_type(type: String) -> String:
	# 简单的映射
	return type # 或者复用 ListingCard 中的逻辑

func _show_fragment_content(fragment: Dictionary):
	# 交易完成后，弹出具体内容展示窗口
	pass

func _show_error(msg: String):
	# 简单的错误弹窗逻辑
	pass
