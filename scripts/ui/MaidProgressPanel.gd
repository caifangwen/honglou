extends Control

@onready var head_maid_loyalty_label = $MarginContainer/VBoxContainer/HeadMaidCard/VBoxContainer/LoyaltyLabel
@onready var head_maid_events_label = $MarginContainer/VBoxContainer/HeadMaidCard/VBoxContainer/EventsLabel
@onready var head_maid_progress_bar = $MarginContainer/VBoxContainer/HeadMaidCard/VBoxContainer/ProgressBar
@onready var head_maid_unlocked_stamp = $MarginContainer/VBoxContainer/HeadMaidCard/UnlockedStamp

@onready var concubine_interaction_label = $MarginContainer/VBoxContainer/ConcubineCard/VBoxContainer/InteractionLabel
@onready var concubine_story_label = $MarginContainer/VBoxContainer/ConcubineCard/VBoxContainer/StoryLabel
@onready var concubine_progress_bar = $MarginContainer/VBoxContainer/ConcubineCard/VBoxContainer/ProgressBar
@onready var concubine_unlocked_stamp = $MarginContainer/VBoxContainer/ConcubineCard/UnlockedStamp

@onready var redemption_silver_label = $MarginContainer/VBoxContainer/RedemptionCard/VBoxContainer/SilverLabel
@onready var redemption_transfer_label = $MarginContainer/VBoxContainer/RedemptionCard/VBoxContainer/TransferLabel
@onready var redemption_progress_bar = $MarginContainer/VBoxContainer/RedemptionCard/VBoxContainer/ProgressBar
@onready var redemption_unlocked_stamp = $MarginContainer/VBoxContainer/RedemptionCard/UnlockedStamp

# 路径卡片引用，用于设置边框颜色
@onready var head_maid_card = $MarginContainer/VBoxContainer/HeadMaidCard
@onready var concubine_card = $MarginContainer/VBoxContainer/ConcubineCard
@onready var redemption_card = $MarginContainer/VBoxContainer/RedemptionCard

func _ready():
	refresh_progress()

func refresh_progress():
	var player_uid = PlayerState.current_uid
	var game_id = PlayerState.current_game_id
	
	if player_uid == "" or game_id == "":
		return
		
	var progress = await MaidProgressionChecker.get_path_progress(player_uid, game_id)
	_update_ui(progress)

func _update_ui(progress: Dictionary):
	# 1. 首席大丫鬟
	var hm = progress.head_maid
	head_maid_loyalty_label.text = "忠诚度：%d/90" % hm.loyalty
	head_maid_events_label.text = "处理事件：%d/5" % hm.events_handled
	
	# 计算综合进度
	var hm_p1 = min(hm.loyalty / 90.0 * 50.0, 50.0)
	var hm_p2 = min(hm.events_handled / 5.0 * 50.0, 50.0)
	head_maid_progress_bar.value = hm_p1 + hm_p2
	
	head_maid_unlocked_stamp.visible = hm.unlocked
	if hm.unlocked:
		head_maid_card.add_theme_stylebox_override("panel", load("res://resources/theme/card_unlocked_style.tres"))
	
	# 2. 收房/姨娘
	var co = progress.concubine
	concubine_interaction_label.text = "互动次数：%d/20" % co.interactions
	concubine_story_label.text = "专属剧情：" + ("已触发" if co.special_story_triggered else "未触发")
	
	var co_p1 = min(co.interactions / 20.0 * 50.0, 50.0)
	var co_p2 = 50.0 if co.special_story_triggered else 0.0
	concubine_progress_bar.value = co_p1 + co_p2
	
	concubine_unlocked_stamp.visible = co.unlocked
	if co.unlocked:
		concubine_card.add_theme_stylebox_override("panel", load("res://resources/theme/card_unlocked_style.tres"))
		
	# 3. 赎身出府
	var re = progress.redemption
	redemption_silver_label.text = "个人积蓄：%d/300两" % re.silver
	redemption_transfer_label.text = "资产转移：" + ("已安全转移" if re.assets_transferred else "未转移")
	
	var re_p1 = min(re.silver / 300.0 * 50.0, 50.0)
	var re_p2 = 50.0 if re.assets_transferred else 0.0
	redemption_progress_bar.value = re_p1 + re_p2
	
	redemption_unlocked_stamp.visible = re.unlocked
	if re.unlocked:
		redemption_card.add_theme_stylebox_override("panel", load("res://resources/theme/card_unlocked_style.tres"))
