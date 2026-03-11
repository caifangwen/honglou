extends Node

# 本地缓存的 session 
var access_token: String = "" 
var refresh_token: String = "" 
var current_uid: String = "" 
var last_username: String = "" # 记录最近一次尝试登录/注册的用户名

# Realtime 相关
var _ws: WebSocketPeer = WebSocketPeer.new()
var _is_ws_connected: bool = false
var _ws_ref: int = 1
var _subscriptions: Dictionary = {} # table_name -> ref
var _heartbeat_timer: float = 0.0
const HEARTBEAT_INTERVAL: float = 30.0

signal auth_success(uid) 
signal auth_error(message) 
signal request_completed(endpoint, response_code, data) 
signal request_failed(endpoint, error) 
signal realtime_update(table_name, data)

func _ready():
	set_process(true)

func _process(delta):
	if _is_ws_connected:
		_ws.poll()
		var state = _ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			# 处理心跳
			_heartbeat_timer += delta
			if _heartbeat_timer >= HEARTBEAT_INTERVAL:
				_heartbeat_timer = 0.0
				_send_ws("phoenix", "heartbeat", {})

			while _ws.get_available_packet_count() > 0:
				var packet = _ws.get_packet()
				var message = packet.get_string_from_utf8()
				_on_ws_message(message)
		elif state == WebSocketPeer.STATE_CLOSED:
			_is_ws_connected = false
			var code = _ws.get_close_code()
			var reason = _ws.get_close_reason()
			print("[Supabase Realtime] WebSocket closed: ", code, " - ", reason)

# ───────────────────────────────────────── 
# 认证：注册 
# ───────────────────────────────────────── 
func sign_up(email, password): 
	last_username = email.split("@")[0] # 默认用户名取邮箱前缀
	var body = JSON.stringify({"email": email, "password": password}) 
	_post(GameConfig.API_AUTH_SIGNUP, body, false) 
 
# ───────────────────────────────────────── 
# 认证：登录 
# ───────────────────────────────────────── 
func sign_in(email, password): 
	if last_username == "": last_username = email.split("@")[0]
	var body = JSON.stringify({"email": email, "password": password}) 
	_post(GameConfig.API_AUTH_LOGIN, body, false) 

# 用户名登录逻辑
func sign_in_with_username(username, password):
	last_username = username
	# 1. 调用 RPC 获取 email (无需 Auth，因为还没登录)
	var res = await db_rpc("get_email_by_username", {"p_username": username}, false)
	if res["code"] == 200 and res["data"] is String and res["data"] != "":
		var email = res["data"]
		sign_in(email, password)
	else:
		var err = "找不到该用户或网络错误"
		auth_error.emit(err)
		push_error("[Supabase] Username login failed: " + err)
 
# ───────────────────────────────────────── 
# 数据库：查询（GET） 
# 用法：await db_get("/rest/v1/players?auth_uid=eq.xxx&select=*") 
# ───────────────────────────────────────── 
func db_get(endpoint): 
	var http = HTTPRequest.new() 
	add_child(http) 
 
	var headers = _build_headers(true) 
	var url = GameConfig.SUPABASE_URL + endpoint
	http.request(url, headers, HTTPClient.METHOD_GET) 
	
	var res = await http.request_completed
	return _on_request_completed_async(res[0], res[1], res[2], res[3], http, endpoint)

# ───────────────────────────────────────── 
# 数据库：插入（POST） 
# ───────────────────────────────────────── 
func db_insert(table, data): 
	var body = JSON.stringify(data) 
	return await _post("/rest/v1/" + table, body, true) 
 
# ───────────────────────────────────────── 
# 数据库：更新（PATCH） 
# 用法：db_update("players", "id=eq.xxx", {"stamina": 5}) 
# ───────────────────────────────────────── 
func db_update(table, filter, data): 
	var body = JSON.stringify(data) 
	return await _patch("/rest/v1/" + table + "?" + filter, body) 

# ───────────────────────────────────────── 
# 数据库：RPC（POST to /rpc/） 
# ───────────────────────────────────────── 
func db_rpc(function_name: String, params: Dictionary = {}, with_auth: bool = true):
	var body = JSON.stringify(params)
	return await _post("/rest/v1/rpc/" + function_name, body, with_auth)
 
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
	var headers = _build_headers(with_auth) 
	var url = endpoint_or_url if endpoint_or_url.begins_with("http") else GameConfig.SUPABASE_URL + endpoint_or_url 
	http.request(url, headers, HTTPClient.METHOD_POST, body) 
	
	var res = await http.request_completed
	return _on_request_completed_async(res[0], res[1], res[2], res[3], http, endpoint_or_url)

func _patch(endpoint_or_url, body): 
	var http = HTTPRequest.new() 
	add_child(http) 
	var headers = _build_headers(true) 
	var url = endpoint_or_url if endpoint_or_url.begins_with("http") else GameConfig.SUPABASE_URL + endpoint_or_url 
	http.request(url, headers, HTTPClient.METHOD_PATCH, body) 
	
	var res = await http.request_completed
	return _on_request_completed_async(res[0], res[1], res[2], res[3], http, endpoint_or_url)

# ───────────────────────────────────────── 
# 数据库：快捷操作（封装自 db_get/db_insert）
# ───────────────────────────────────────── 
func get_from_table(table_name: String):
	var endpoint = "/rest/v1/" + table_name + "?select=*"
	var res = await db_get(endpoint)
	# 为了兼容 SupabaseTest.gd，这里手动 emit 一个带 table_name 的信号
	request_completed.emit(table_name, res["code"], res["data"])
	return res

func insert_into_table(table_name: String, data: Dictionary):
	var res = await db_insert(table_name, data)
	# 为了兼容 SupabaseTest.gd，这里手动 emit 一个带 table_name 的信号
	request_completed.emit(table_name, res["code"], res["data"])
	return res

func update_table(table_name: String, filter: String, data: Dictionary):
	var res = await db_update(table_name, filter, data)
	# 为了兼容 SupabaseTest.gd，这里手动 emit 一个带 table_name 的信号
	request_completed.emit(table_name, res["code"], res["data"])
	return res

# ───────────────────────────────────────── 
# 内部：统一响应处理 
# ───────────────────────────────────────── 
func _on_request_completed_async(result, response_code, _headers, body, http, endpoint: String = ""): 
	http.queue_free() 
 
	if result != HTTPRequest.RESULT_SUCCESS:
		var net_err = "网络连接失败 (Result: %d)" % result
		push_error("[Supabase] " + net_err)
		
		# 如果是认证相关的请求报错，单独发 auth_error
		if endpoint.contains("/auth/v1/"):
			auth_error.emit(net_err)
			
		request_failed.emit(endpoint, net_err)
		return {"code": 0, "data": null, "error": net_err}

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
		
		# 如果是认证相关的请求报错，单独发 auth_error
		if endpoint.contains("/auth/v1/"):
			auth_error.emit(err_msg)
		
		request_failed.emit(endpoint, err_msg) 
		return {"code": response_code, "data": parsed, "error": err_msg}
 
	# 登录/注册成功：缓存 token 
	if parsed is Dictionary and parsed.has("access_token"): 
		access_token = str(parsed.get("access_token", "")) 
		refresh_token = str(parsed.get("refresh_token", "")) 
		var user_data = parsed.get("user", {})
		if user_data is Dictionary:
			current_uid = str(user_data.get("id", ""))
			if last_username == "":
				last_username = str(user_data.get("email", "")).split("@")[0]
		auth_success.emit(current_uid) 
 
	var response = {"code": response_code, "data": parsed}
	request_completed.emit(endpoint, response_code, parsed) 

	# 登录成功后自动连接实时更新
	if parsed is Dictionary and parsed.has("access_token"):
		_connect_realtime()

	return response

# ───────────────────────────────────────── 
# Realtime 核心逻辑 (Minimal Phoenix Protocol)
# ───────────────────────────────────────── 

func _connect_realtime():
	if _is_ws_connected: return
	
	var ws_url = GameConfig.SUPABASE_URL.replace("https://", "wss://") + "/realtime/v1/websocket?apikey=" + GameConfig.SUPABASE_ANON_KEY + "&vsn=1.0.0"
	
	# Godot 4 中默认使用 TLSOptions.client() 即可
	# 如果仍然有 TLS 握手错误，可能需要检查系统证书或防火墙
	var err = _ws.connect_to_url(ws_url)
	if err != OK:
		push_error("[Supabase Realtime] WebSocket connection failed: " + str(err))
		return
	
	_is_ws_connected = true
	print("[Supabase Realtime] Connecting to WebSocket...")

func subscribe_to_table(table_name: String):
	if not _is_ws_connected:
		_connect_realtime()
		# 等待连接成功
		await get_tree().create_timer(1.0).timeout
	
	var topic = "realtime:public:" + table_name
	_subscriptions[table_name] = str(_ws_ref)
	_send_ws(topic, "phx_join", {})
	print("[Supabase Realtime] Subscribed to table: ", table_name)

func _send_ws(topic: String, event: String, payload: Dictionary):
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
		
	var msg = {
		"topic": topic,
		"event": event,
		"payload": payload,
		"ref": str(_ws_ref)
	}
	_ws.send_text(JSON.stringify(msg))
	_ws_ref += 1

func _on_ws_message(message: String):
	var parsed = JSON.parse_string(message)
	if parsed == null: return
	
	var topic = parsed.get("topic", "")
	var event = parsed.get("event", "")
	var payload = parsed.get("payload", {})
	
	# 心跳保持
	if topic == "phoenix" and event == "heartbeat":
		return
	
	# 处理数据变更
	if event == "postgres_changes":
		var table = payload.get("data", {}).get("table", "")
		realtime_update.emit(table, payload.get("data", {}))
		print("[Supabase Realtime] Data change in ", table)

# 定时心跳
func _on_heartbeat_timer():
	if _is_ws_connected and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send_ws("phoenix", "heartbeat", {})
