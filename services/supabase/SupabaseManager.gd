extends Node

## SupabaseManager.gd - Supabase 服务统一入口
## 负责：连接初始化、用户鉴权、实时订阅
## 数据读写操作已委托给 SupabaseDB.gd

# 本地缓存的 session
var access_token: String = ""
var refresh_token: String = ""
var current_uid: String = ""
var last_username: String = ""

# 本地开发模式标志
var _is_local_mode: bool = false

# Realtime 相关
var _ws: WebSocketPeer = WebSocketPeer.new()
var _is_ws_connected: bool = false
var _ws_ref: int = 1
var _subscriptions: Dictionary = {}
var _heartbeat_timer: float = 0.0
const HEARTBEAT_INTERVAL: float = 30.0

# 数据库操作委托
var _db: Node = null

signal auth_success(uid)
signal auth_error(message)
signal request_completed(endpoint, response_code, data)
signal request_failed(endpoint, error)
signal realtime_update(table_name, data)

func _ready():
	_check_local_mode()
	_init_database()
	set_process(true)

func _init_database() -> void:
	# 初始化 SupabaseDB 实例
	_db = load("res://services/supabase/SupabaseDB.gd").new()
	_db.set_manager(self)
	add_child(_db)
	# 转发信号
	_db.request_completed.connect(func(e, c, d): request_completed.emit(e, c, d))
	_db.request_failed.connect(func(e, err): request_failed.emit(e, err))

func _check_local_mode() -> void:
	await get_tree().process_frame
	_is_local_mode = GameConfig.USE_LOCAL_DB
	print("[SupabaseManager] 本地模式：", _is_local_mode)

func _process(delta):
	if _is_ws_connected:
		_ws.poll()
		var state = _ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
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
	last_username = email.split("@")[0]

	if _is_local_mode:
		_simulate_local_auth(email, password)
		return

	var body = JSON.stringify({"email": email, "password": password})
	_post_auth(GameConfig.API_AUTH_SIGNUP, body, false)

# ─────────────────────────────────────────
# 认证：登录
# ─────────────────────────────────────────
func sign_in(email, password):
	if last_username == "": last_username = email.split("@")[0]

	if _is_local_mode:
		_simulate_local_auth(email, password)
		return

	var body = JSON.stringify({"email": email, "password": password})
	_post_auth(GameConfig.API_AUTH_LOGIN, body, false)

# 用户名登录逻辑
func sign_in_with_username(username, password):
	last_username = username

	if _is_local_mode:
		_simulate_local_auth(username + "@local", password)
		return

	var res = await db_rpc("get_email_by_username", {"p_username": username}, false)
	if res["code"] == 200 and res["data"] is String and res["data"] != "":
		var email = res["data"]
		sign_in(email, password)
	else:
		var err = "找不到该用户或网络错误"
		auth_error.emit(err)
		push_error("[Supabase] Username login failed: " + err)

# ─────────────────────────────────────────
# 本地模式：模拟认证
# ─────────────────────────────────────────
func _simulate_local_auth(email: String, password: String) -> void:
	var username = email.split("@")[0]
	var hash = hash_string(username)
	var simulated_uid = "%08x-0000-0000-0000-000000000000" % hash

	access_token = "local-token-" + username
	refresh_token = "local-refresh-" + username
	current_uid = simulated_uid

	print("[SupabaseManager] 本地登录模拟：email=%s, uid=%s" % [email, simulated_uid])
	auth_success.emit(simulated_uid)

func hash_string(s: String) -> int:
	var hash = 5381
	for c in s:
		hash = ((hash << 5) + hash) + c.unicode_at(0)
		hash = hash & 0x7FFFFFFF
	return hash

# 认证专用的 POST（不经过 SupabaseDB）
func _post_auth(endpoint_or_url, body, with_auth):
	var http = HTTPRequest.new()
	add_child(http)
	var headers = _build_auth_headers(with_auth)
	var url = endpoint_or_url if endpoint_or_url.begins_with("http") else GameConfig.SUPABASE_URL + endpoint_or_url
	http.request(url, headers, HTTPClient.METHOD_POST, body)

	var res = await http.request_completed
	return _on_auth_response_async(res[0], res[1], res[2], res[3], http, endpoint_or_url)

func _build_auth_headers(with_auth):
	var headers = PackedStringArray([
		"Content-Type: application/json",
		"Prefer: return=representation"
	])

	if _is_local_mode:
		headers.append("apikey: local-dev-key")
		headers.append("Prefer: return=representation,merge-duplicates")
	else:
		headers.append("apikey: " + GameConfig.SUPABASE_ANON_KEY)
		if with_auth and access_token != "":
			headers.append("Authorization: Bearer " + access_token)

	return headers

func _on_auth_response_async(result, response_code, _headers, body, http, endpoint: String = ""):
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		var net_err = "网络连接失败 (Result: %d)" % result
		push_error("[Supabase] " + net_err)
		if endpoint.contains("/auth/v1/"):
			auth_error.emit(net_err)
		return {"code": 0, "data": null, "error": net_err}

	var text = body.get_string_from_utf8()
	var parsed = JSON.parse_string(text)

	if response_code >= 400 or parsed == null:
		var err_msg = text
		if parsed is Dictionary:
			if parsed.has("msg"): err_msg = parsed["msg"]
			elif parsed.has("error_description"): err_msg = parsed["error_description"]
			elif parsed.has("error"): err_msg = parsed["error"]

		if err_msg == "": err_msg = "HTTP %d" % response_code
		push_error("[Supabase Error %d] %s" % [response_code, err_msg])

		if endpoint.contains("/auth/v1/"):
			auth_error.emit(err_msg)
		return {"code": response_code, "data": parsed, "error": err_msg}

	if parsed is Dictionary and (parsed.has("access_token") or parsed.has("email")):
		if parsed.has("access_token"):
			access_token = str(parsed.get("access_token", ""))
			refresh_token = str(parsed.get("refresh_token", ""))

		var user_data = parsed.get("user", parsed)
		if user_data is Dictionary:
			current_uid = str(user_data.get("id", ""))
			if last_username == "":
				last_username = str(user_data.get("email", "")).split("@")[0]

		auth_success.emit(current_uid)
		_connect_realtime()

	return {"code": response_code, "data": parsed}

# ─────────────────────────────────────────
# 数据库操作：转发给 SupabaseDB（向后兼容）
# ─────────────────────────────────────────
func db_get(endpoint):
	return await _db.db_get(endpoint)

func db_insert(table, data):
	return await _db.db_insert(table, data)

func db_update(table, filter, data):
	return await _db.db_update(table, filter, data)

func db_delete(table, filter):
	return await _db.db_delete(table, filter)

func db_rpc(function_name: String, params: Dictionary = {}, with_auth: bool = true):
	return await _db.db_rpc(function_name, params, with_auth)

func get_from_table(table_name: String):
	return await _db.get_from_table(table_name)

func insert_into_table(table_name: String, data: Dictionary):
	return await _db.insert_into_table(table_name, data)

func update_table(table_name: String, filter: String, data: Dictionary):
	return await _db.update_table(table_name, filter, data)

func invoke_function(function_name: String, payload: Dictionary = {}):
	return await _db.invoke_function(function_name, payload)

func query(table_name: String, filters: Dictionary = {}):
	return await _db.query(table_name, filters)

# ─────────────────────────────────────────
# Realtime 核心逻辑
# ─────────────────────────────────────────
func _connect_realtime():
	if _is_ws_connected: return

	var ws_url = GameConfig.SUPABASE_URL.replace("https://", "wss://") + "/realtime/v1/websocket?apikey=" + GameConfig.SUPABASE_ANON_KEY + "&vsn=1.0.0"

	var err = _ws.connect_to_url(ws_url)
	if err != OK:
		push_error("[Supabase Realtime] WebSocket connection failed: " + str(err))
		return

	_is_ws_connected = true
	print("[Supabase Realtime] Connecting to WebSocket...")

func subscribe_to_table(table_name: String):
	if not _is_ws_connected:
		_connect_realtime()
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

	if topic == "phoenix" and event == "heartbeat":
		return

	if event == "postgres_changes":
		var change_data = payload.get("data", {})
		var table = change_data.get("table", "")
		if table != "":
			realtime_update.emit(table, change_data)
			print("[Supabase Realtime] Data change in ", table, " - type: ", change_data.get("type", ""))

# ─────────────────────────────────────────
# Realtime：订阅频道（简化版）
# ─────────────────────────────────────────
func channel(channel_name: String):
	return RumorChannel.new(self, channel_name)

class RumorChannel:
	var _manager: Node
	var _name: String
	var _callback: Callable

	func _init(manager, name):
		_manager = manager
		_name = name

	func on(_event_type, _config, callback):
		_callback = callback
		return self

	func subscribe():
		_manager._send_ws("realtime", "join", {"topic": "realtime:public"})
		_manager.realtime_update.connect(func(table, data):
			if table == "rumors":
				_callback.call({"eventType": "INSERT", "new": data})
		)
		return self
