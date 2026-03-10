extends Node

# 本地缓存的 session 
var access_token: String = "" 
var refresh_token: String = "" 
var current_uid: String = "" 
 
signal auth_success(uid) 
signal auth_error(message) 
signal request_complete(response) 
signal request_failed(error) 
 
# ───────────────────────────────────────── 
# 认证：注册 
# ───────────────────────────────────────── 
func sign_up(email, password): 
	var body = JSON.stringify({"email": email, "password": password}) 
	_post(GameConfig.API_AUTH_SIGNUP, body, false) 
 
# ───────────────────────────────────────── 
# 认证：登录 
# ───────────────────────────────────────── 
func sign_in(email, password): 
	var body = JSON.stringify({"email": email, "password": password}) 
	_post(GameConfig.API_AUTH_LOGIN, body, false) 
 
# ───────────────────────────────────────── 
# 数据库：查询（GET） 
# 用法：db_get("/rest/v1/players?auth_uid=eq.xxx&select=*") 
# ───────────────────────────────────────── 
func db_get(endpoint): 
	var http = HTTPRequest.new() 
	add_child(http) 
	http.request_completed.connect(_on_request_completed.bind(http)) 
 
	var headers = _build_headers(true) 
	http.request(GameConfig.SUPABASE_URL + endpoint, headers, HTTPClient.METHOD_GET) 
 
# ───────────────────────────────────────── 
# 数据库：插入（POST） 
# ───────────────────────────────────────── 
func db_insert(table, data): 
	var body = JSON.stringify(data) 
	_post("/rest/v1/" + table, body, true) 
 
# ───────────────────────────────────────── 
# 数据库：更新（PATCH） 
# 用法：db_update("players", "id=eq.xxx", {"stamina": 5}) 
# ───────────────────────────────────────── 
func db_update(table, filter, data): 
	var body = JSON.stringify(data) 
	_patch("/rest/v1/" + table + "?" + filter, body) 
 
# ───────────────────────────────────────── 
# 内部：构建请求头 
# ───────────────────────────────────────── 
func _build_headers(with_auth): 
	var headers = PackedStringArray([ 
		"Content-Type: application/json", 
		"apikey: " + GameConfig.SUPABASE_ANON_KEY, 
		"Prefer: return=representation"   # 插入/更新后返回结果 
	]) 
	if with_auth and access_token != "": 
		headers.append("Authorization: Bearer " + access_token) 
	return headers 
 
func _post(endpoint_or_url, body, with_auth): 
	var http = HTTPRequest.new() 
	add_child(http) 
	http.request_completed.connect(_on_request_completed.bind(http)) 
	var headers = _build_headers(with_auth) 
	var url = endpoint_or_url if endpoint_or_url.begins_with("http") else GameConfig.SUPABASE_URL + endpoint_or_url 
	http.request(url, headers, HTTPClient.METHOD_POST, body) 
 
func _patch(endpoint_or_url, body): 
	var http = HTTPRequest.new() 
	add_child(http) 
	http.request_completed.connect(_on_request_completed.bind(http)) 
	var headers = _build_headers(true) 
	var url = endpoint_or_url if endpoint_or_url.begins_with("http") else GameConfig.SUPABASE_URL + endpoint_or_url 
	http.request(url, headers, HTTPClient.METHOD_PATCH, body) 
 
# ───────────────────────────────────────── 
# 内部：统一响应处理 
# ───────────────────────────────────────── 
func _on_request_completed(result, response_code, _headers, body, http): 
	http.queue_free() 
 
	if result != HTTPRequest.RESULT_SUCCESS:
		var net_err = "网络连接失败 (Result: %d)" % result
		push_error("[Supabase] " + net_err)
		request_failed.emit(net_err)
		return

	var text = body.get_string_from_utf8() 
	var parsed = JSON.parse_string(text) 
 
	if response_code >= 400 or parsed == null: 
		# 如果是 Supabase 返回的错误 JSON，通常包含 msg 或 error 字段
		var err_msg = text
		if parsed is Dictionary:
			if parsed.has("msg"): err_msg = parsed["msg"]
			elif parsed.has("error_description"): err_msg = parsed["error_description"]
			elif parsed.has("error"): err_msg = parsed["error"]
		
		if err_msg == "": err_msg = "HTTP %d" % response_code
		
		push_error("[Supabase Error %d] %s" % [response_code, err_msg])
		request_failed.emit(err_msg) 
		return 
 
	# 登录/注册成功：缓存 token 
	if parsed is Dictionary and parsed.has("access_token"): 
		access_token = parsed["access_token"] 
		refresh_token = parsed.get("refresh_token", "") 
		current_uid = parsed.get("user", {}).get("id", "") 
		auth_success.emit(current_uid) 
		return 
 
	request_complete.emit({"code": response_code, "data": parsed}) 
