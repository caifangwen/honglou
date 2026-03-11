extends Control 
  
@onready var email_input    = $CenterContainer/LoginPanel/EmailInput 
@onready var password_input = $CenterContainer/LoginPanel/PasswordInput 
@onready var error_label    = $CenterContainer/LoginPanel/ErrorLabel 
@onready var loading_label  = $CenterContainer/LoginPanel/LoadingLabel 
@onready var login_btn      = $CenterContainer/LoginPanel/LoginBtn 
@onready var register_btn   = $CenterContainer/LoginPanel/RegisterBtn 
@onready var quick_login_btn = $CenterContainer/LoginPanel/QuickLoginBtn
  
var _is_signing_in: bool = false

func _ready() -> void: 
	error_label.hide() 
	loading_label.hide() 
	SupabaseManager.auth_success.connect(_on_auth_success) 
	SupabaseManager.auth_error.connect(_on_auth_error) 
  
func _on_login_btn_pressed() -> void: 
	_is_signing_in = true
	_set_loading(true) 
	SupabaseManager.sign_in(email_input.text.strip_edges(), 
							password_input.text) 
  
func _on_register_btn_pressed() -> void: 
	_is_signing_in = false
	_set_loading(true) 
	SupabaseManager.sign_up(email_input.text.strip_edges(), 
							password_input.text) 

func _on_quick_login_btn_pressed() -> void:
	_is_signing_in = true
	_set_loading(true)
	# 模拟测试账号快捷登录
	var test_email = "test_steward@example.com"
	var test_pass  = "123456"
	email_input.text = test_email
	password_input.text = test_pass
	SupabaseManager.sign_in(test_email, test_pass)
  
func _on_auth_success(uid: String) -> void: 
	_set_loading(false) 
	# 查询该 uid 是否已建立角色 
	var res = await SupabaseManager.db_get( 
		"/rest/v1/players?auth_uid=eq.%s&select=id,role_class,character_name" % uid 
	) 
	_on_player_check(res) 
  
func _on_player_check(response: Dictionary) -> void: 
	var data = response["data"] 
	if data is Array and data.size() > 0: 
		# 已有角色 → 加载状态 → 进 Hub 
		var p = data[0] 
		PlayerState.uid = SupabaseManager.current_uid
		PlayerState.load_from_db(p)
		get_tree().change_scene_to_file("res://scenes/Hub.tscn") 
	else: 
		# 新玩家 → 角色选择 
		get_tree().change_scene_to_file("res://scenes/RoleSelect.tscn") 
  
func _on_auth_error(message: String) -> void: 
	# 如果登录时报错 "Invalid login credentials"，可能是账号还没注册，自动注册一次
	if _is_signing_in and ("invalid login" in message.to_lower() or "invalid_grant" in message.to_lower()):
		_is_signing_in = false # 改成注册流程，防止死循环
		SupabaseManager.sign_up(email_input.text, password_input.text)
		return
		
	_set_loading(false) 
	error_label.text = _localize_error(message) 
	error_label.show() 
  
func _set_loading(on: bool) -> void: 
	loading_label.visible = on 
	login_btn.disabled = on 
	register_btn.disabled = on 
	quick_login_btn.disabled = on
  
func _localize_error(raw: String) -> String: 
	var low = raw.to_lower()
	if "invalid login" in low or "invalid_grant" in low: 
		return "邮箱或密码错误" 
	if "user already registered" in low: 
		return "该邮箱已注册，请直接登录" 
	if "password should be" in low: 
		return "密码至少需要6位" 
	if "network" in low or "result:" in low:
		return "网络连接失败，请检查 URL 配置或网络"
	return "错误: " + raw 
