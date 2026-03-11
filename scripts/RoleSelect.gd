extends Control 
  
# 阶层配置数据 
const ROLE_DATA = { 
	"steward": { 
		"display": "管家", 
		"tagline": "掌握分配权，左右家族命运", 
		"desc": "每日6点精力，掌控公中银库，可克扣、采办、搜检。\n风险最高，收益最大。", 
		"stamina": 6, 
		"ability": "特权：维护明账与暗账两套账本" 
	}, 
	"master": { 
		"display": "主子", 
		"tagline": "以名望为护城河，诗社称霸", 
		"desc": "参与海棠诗社，积累名望值。\n名望≥120可强制撤销管家决策。", 
		"stamina": 6, 
		"ability": "特权：发起联名谏言" 
	}, 
	"servant": { 
		"display": "丫鬟·小厮", 
		"tagline": "人微言轻，却掌握最多秘密", 
		"desc": "每日8点精力，挂机监听情报，经营地下情报网。\n三条逆袭路径：首席丫鬟、收房、赎身。", 
		"stamina": 8, 
		"ability": "特权：跨阵营传话，唯一可篡改口信的阶层" 
	}, 
	"elder": { 
		"display": "元老", 
		"tagline": "一言可定人生死", 
		"desc": "上一局积分最高者专属。\n拥有最高裁决权，可厌弃任意玩家。", 
		"stamina": 6, 
		"ability": "特权：纠纷最终裁决、额外赏赐分配" 
	}, 
	"guest": { 
		"display": "清客", 
		"tagline": "搅局者，预言者，局外人", 
		"desc": "游走于各方势力之间，以情报和诅咒左右局势。\n无固定阵营，收益来自混乱。", 
		"stamina": 6, 
		"ability": "特权：扎小人、预视下旬事件、走街串巷散布情报" 
	} 
} 
  
var selected_role: String = "" 
  
@onready var confirm_btn          = $ConfirmBtn 
@onready var selected_info_panel  = $SelectedInfoPanel 
@onready var role_name_label      = $SelectedInfoPanel/RoleNameLabel 
@onready var role_desc_label      = $SelectedInfoPanel/RoleDescLabel 
@onready var stamina_label        = $SelectedInfoPanel/StaminaLabel 
@onready var ability_label        = $SelectedInfoPanel/SpecialAbilityLabel 
@onready var character_name_input = $CharacterNameInput 
@onready var error_label          = $ErrorLabel 
  
func _ready() -> void: 
	confirm_btn.disabled = true 
	selected_info_panel.hide() 
	error_label.hide() 
  
	# 绑定每个阶层卡片的点击 
	for role_key in ROLE_DATA: 
		var card = get_node_or_null("RoleGrid/" + _role_node_name(role_key)) 
		if card: 
			card.gui_input.connect(_on_card_clicked.bind(role_key)) 
  
func _role_node_name(role_key: String) -> String: 
	match role_key: 
		"steward": return "StewardCard" 
		"master":  return "MasterCard" 
		"servant": return "ServantCard" 
		"elder":   return "ElderCard" 
		"guest":   return "GuestCard" 
	return "" 
  
func _on_card_clicked(event: InputEvent, role_key: String) -> void: 
	if not event is InputEventMouseButton: return 
	if not event.pressed: return 
	# 元老需要资格（本阶段直接锁定） 
	if role_key == "elder": 
		error_label.text = "元老资格需上一局最高积分才可解锁" 
		error_label.show() 
		return 
	error_label.hide() 
	selected_role = role_key 
	_update_info_panel(role_key) 
	confirm_btn.disabled = false 
  
func _update_info_panel(role_key: String) -> void: 
	var d = ROLE_DATA[role_key] 
	role_name_label.text    = d["display"] 
	role_desc_label.text    = d["desc"] 
	stamina_label.text      = "精力：%d 点/日" % d["stamina"] 
	ability_label.text      = d["ability"] 
	selected_info_panel.show() 
  
func _on_confirm_btn_pressed() -> void: 
	var char_name = character_name_input.text.strip_edges() 
	if char_name.length() < 2: 
		error_label.text = "角色名至少需要2个字" 
		error_label.show() 
		return 
	if selected_role == "": 
		error_label.text = "请先选择阶层" 
		error_label.show() 
		return 
  
	confirm_btn.disabled = true 
	var role_d = ROLE_DATA[selected_role] 
  
	# 写入 players 表 
	var response = await SupabaseManager.db_insert("players", { 
		"auth_uid":        SupabaseManager.current_uid, 
		"display_name":    char_name, 
		"character_name":  char_name, 
		"role_class":      selected_role, 
		"stamina":         role_d["stamina"], 
		"stamina_max":     role_d["stamina"], 
		"current_game_id": "00000000-0000-0000-0000-000000000001"  # 测试局 
	}) 
	
	if response["code"] == 201:
		_on_insert_complete(response)
	else:
		_on_insert_failed(response.get("error", "未知错误"))

func _on_insert_complete(response: Dictionary) -> void: 
	var data = response["data"] 
	# Supabase 插入返回数组 
	if data is Array and data.size() > 0: 
		var p = data[0] 
		PlayerState.load_from_db(p)
		get_tree().change_scene_to_file("res://scenes/Hub.tscn") 
	# 注意：如果是其他请求完成也会触发这个信号，所以最好在发送请求前绑定 CONNECT_ONE_SHOT 或者在这里判断 endpoint
  
func _on_insert_failed(error: String) -> void: 
	confirm_btn.disabled = false 
	error_label.text = "创建角色失败：" + error 
	error_label.show() 
