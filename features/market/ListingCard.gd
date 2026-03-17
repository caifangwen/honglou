extends Control

# ListingCard.gd
# 每个集市卡片显示：情报类型、价值星级、价格、预览及购买按钮

signal purchase_pressed(trade_id)
signal preview_pressed(trade_id, scene_name)

@onready var type_icon = $HBox/TypeIcon
@onready var type_label = $HBox/TypeLabel
@onready var stars_label = $HBox/StarsLabel
@onready var price_label = $HBox/PriceLabel
@onready var preview_btn = $HBox/PreviewBtn
@onready var buy_btn = $HBox/BuyBtn

var _trade_id: String = ""
var _scene_name: String = ""

func setup(data: Dictionary):
	_trade_id = data.get("trade_id", "")
	_scene_name = data.get("scene", "unknown")
	
	# 设置类型
	var type_key = data.get("intel_type", "unknown")
	type_label.text = _localize_type(type_key)
	
	# 设置星级 (★★★☆☆)
	var value_level = data.get("value_level", 1)
	var stars = ""
	for i in range(5):
		stars += "★" if i < value_level else "☆"
	stars_label.text = stars
	
	# 设置价格
	var silver = data.get("price_silver", 0)
	var qi = data.get("price_qi", 0)
	if silver > 0:
		price_label.text = "%d 两" % silver
	elif qi > 0:
		price_label.text = "%d 气数" % qi
	else:
		price_label.text = "免费"
	
	# 连接按钮信号
	if not preview_btn.pressed.is_connected(_on_preview_pressed):
		preview_btn.pressed.connect(_on_preview_pressed)
	if not buy_btn.pressed.is_connected(_on_buy_pressed):
		buy_btn.pressed.connect(_on_buy_pressed)

func _on_preview_pressed():
	preview_pressed.emit(_trade_id, _scene_name)

func _on_buy_pressed():
	purchase_pressed.emit(_trade_id)

func _localize_type(type: String) -> String:
	var mapping = {
		"account_leak": "账目漏洞",
		"gift_record": "私相授受",
		"private_action": "行踪诡秘",
		"visitor_info": "访客密谈",
		"elder_favor": "得宠动态"
	}
	return mapping.get(type, "未知情报")
