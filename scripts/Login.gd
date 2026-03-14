extends Control 
  
@onready var email_input    = $CenterContainer/LoginPanel/EmailInput 
@onready var password_input = $CenterContainer/LoginPanel/PasswordInput 
@onready var error_label    = $CenterContainer/LoginPanel/ErrorLabel 
@onready var loading_label  = $CenterContainer/LoginPanel/LoadingLabel 
@onready var login_btn      = $CenterContainer/LoginPanel/LoginBtn 
@onready var register_btn   = $CenterContainer/LoginPanel/RegisterBtn 
@onready var quick_login_grid = $CenterContainer/LoginPanel/QuickLoginGrid
  
var _is_signing_in: bool = false

var test_accounts = [
	{"name": "凤姐 (管家)", "email": "fengjie@example.com", "pass": "123456"},
	{"name": "平儿 (管家)", "email": "pinger@example.com", "pass": "123456"},
	{"name": "袭人 (丫鬟)", "email": "xiren@example.com", "pass": "123456"},
	{"name": "晴雯 (丫鬟)", "email": "qingwen@example.com", "pass": "123456"},
	{"name": "贾母 (元老)", "email": "jiamu@example.com", "pass": "123456"}
]

func _ready() -> void: 
	error_label.hide() 
	loading_label.hide() 
	SupabaseManager.auth_success.connect(_on_auth_success) 
	SupabaseManager.auth_error.connect(_on_auth_error) 
	
	_setup_quick_login_buttons()

func _setup_quick_login_buttons() -> void:
	for acc in test_accounts:
		var btn = Button.new()
		btn.text = acc["name"]
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_on_quick_account_pressed.bind(acc))
		quick_login_grid.add_child(btn)

func _on_quick_account_pressed(acc: Dictionary) -> void:
	_is_signing_in = true
	_set_loading(true)
	email_input.text = acc["email"]
	password_input.text = acc["pass"]
	SupabaseManager.sign_in(acc["email"], acc["pass"])

func _on_login_btn_pressed() -> void: 
	_is_signing_in = true
	_set_loading(true) 
	var input = email_input.text.strip_edges()
	if "@" in input:
		SupabaseManager.sign_in(input, password_input.text) 
	else:
		SupabaseManager.sign_in_with_username(input, password_input.text) 
  
func _on_register_btn_pressed() -> void: 
	_is_signing_in = false
	_set_loading(true) 
	SupabaseManager.sign_up(email_input.text.strip_edges(), 
							password_input.text) 
  
func _on_auth_success(uid: String) -> void: 
	_set_loading(false) 
	# 查询该 uid 是否已建立角色 
	var res = await SupabaseManager.db_get( 
		"/rest/v1/players?auth_uid=eq.%s&select=*" % uid 
	) 
	_on_player_check(res) 
  
func _on_player_check(response: Dictionary) -> void: 
	var data = response["data"] 
	if data is Array and data.size() > 0: 
		# 已有角色 → 加载状态 → 进 Hub 
		var p = data[0] 
		PlayerState.uid = SupabaseManager.current_uid
		PlayerState.load_from_db(p)
		
		# 如果是管家，额外获取私产信息并合并
		if PlayerState.role_class == "steward":
			var s_res = await SupabaseManager.db_get(
				"/rest/v1/steward_accounts?steward_uid=eq.%s&game_id=eq.%s&select=private_assets" % [PlayerState.uid, PlayerState.current_game_id]
			)
			if s_res["code"] == 200 and not s_res["data"].is_empty():
				PlayerState.silver = s_res["data"][0].get("private_assets", PlayerState.silver)
		
		get_tree().change_scene_to_file("res://scenes/Hub.tscn") 
	else: 
		# 快捷登录时，如果发现没有角色，自动创建一个 (仅限测试环境)
		if _is_signing_in and "@example.com" in email_input.text:
			await _auto_create_test_player()
			return
			
		# 新玩家 → 角色选择 
		get_tree().change_scene_to_file("res://scenes/RoleSelect.tscn") 

func _auto_create_test_player() -> void:
	var role = "steward"
	var char_name = "凤姐"
	var username = email_input.text.split("@")[0]
	
	# 根据邮箱自动映射角色
	if "xiren" in username: role = "servant"; char_name = "袭人"
	elif "qingwen" in username: role = "servant"; char_name = "晴雯"
	elif "jiamu" in username: role = "elder"; char_name = "贾母"
	elif "pinger" in username: role = "steward"; char_name = "平儿"
	elif "fengjie" in username: role = "steward"; char_name = "凤姐"
	
	var new_player = {
		"auth_uid": SupabaseManager.current_uid,
		"username": username,
		"display_name": username, # 初始显示名使用用户名
		"character_name": char_name,
		"role_class": role,
		"current_game_id": GameState.current_game_id,
		"silver": 100,
		"stamina": 6,
		"stamina_max": 6,
		"private_silver": 0,
		"reputation": 50,
		"qi_points": 100
	}
	
	var res = await SupabaseManager.db_insert("players", new_player)
	if res["code"] == 201:
		PlayerState.load_from_db(res["data"][0])
		get_tree().change_scene_to_file("res://scenes/Hub.tscn")
	else:
		error_label.text = "自动创建角色失败: " + str(res.get("error", "Unknown"))
		error_label.show()
		_set_loading(false)
  
func _on_auth_error(message: String) -> void: 
	_set_loading(false) 
	error_label.text = _localize_error(message) 
	error_label.show() 
	print("[Login] Auth error: ", message)
  
func _set_loading(on: bool) -> void: 
	loading_label.visible = on 
	login_btn.disabled = on 
	register_btn.disabled = on 
	for btn in quick_login_grid.get_children():
		if btn is Button:
			btn.disabled = on
  
func _localize_error(raw: String) -> String: 
	var low = raw.to_lower()
	if "invalid login" in low or "invalid_grant" in low: 
		return "邮箱或密码错误" 
	if "user already registered" in low: 
		return "该邮箱已注册，请直接登录" 
	if "email not confirmed" in low:
		return "该邮箱尚未验证，请检查邮件"
	if "password should be" in low: 
		return "密码至少需要6位" 
	if "network" in low or "result:" in low:
		return "网络连接失败，请检查 URL 配置或网络"
	return "错误: " + raw 
