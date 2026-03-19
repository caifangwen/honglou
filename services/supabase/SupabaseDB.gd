extends Node

## SupabaseDB.gd - 数据库读写操作封装
## 负责所有数据查询、插入、更新、删除操作

signal request_completed(endpoint, response_code, data)
signal request_failed(endpoint, error)

# 依赖注入：从 SupabaseManager 获取认证信息
var _manager: Node = null

func set_manager(manager: Node) -> void:
	_manager = manager

# ─────────────────────────────────────────
# 数据库：查询（GET）
# 用法：await db_get("/rest/v1/players?auth_uid=eq.xxx&select=*")
# ─────────────────────────────────────────
func db_get(endpoint):
	if _manager._is_local_mode:
		# 本地模式：检查是否是 mock 表查询
		if endpoint.contains("/players"):
			# 解析查询参数
			var filters = {}
			if endpoint.contains("current_game_id=eq."):
				var parts = endpoint.split("current_game_id=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["current_game_id"] = value
			if endpoint.contains("auth_uid=eq."):
				var parts = endpoint.split("auth_uid=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["auth_uid"] = value
			if endpoint.contains("id=eq."):
				var parts = endpoint.split("id=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["id"] = value
			if endpoint.contains("role_class=eq."):
				var parts = endpoint.split("role_class=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["role_class"] = value

			print("[SupabaseDB] Using mock select for players with filters: ", filters)
			var result = await MockDatabase.mock_select_players(filters)
			return {"code": 200, "data": result}

		elif endpoint.contains("/maid_relationships"):
			# 解析查询参数
			var filters = {}
			if endpoint.contains("player_b_uid=eq."):
				var parts = endpoint.split("player_b_uid=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["player_b_uid"] = value
			if endpoint.contains("status=eq."):
				var parts = endpoint.split("status=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["status"] = value
			if endpoint.contains("relation_type=eq."):
				var parts = endpoint.split("relation_type=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["relation_type"] = value
			# 只查询明确的 id 过滤，避免误解析 select 语句
			if endpoint.contains("&id=eq."):
				var parts = endpoint.split("&id=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["id"] = value
			
			print("[SupabaseDB] Using mock select for maid_relationships with filters: ", filters)
			var result = await MockDatabase.mock_select_maid_relationships(filters)
			return {"code": 200, "data": result}
		
		elif endpoint.contains("/notifications"):
			var filters = {}
			if endpoint.contains("player_uid=eq."):
				var parts = endpoint.split("player_uid=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["player_uid"] = value

			print("[SupabaseDB] Using mock select for notifications with filters: ", filters)
			var result = await MockDatabase.mock_select_notifications(filters)
			return {"code": 200, "data": result}

		elif endpoint.contains("/steward_accounts"):
			var filters = {}
			if endpoint.contains("steward_uid=eq."):
				var parts = endpoint.split("steward_uid=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["steward_uid"] = value
			if endpoint.contains("game_id=eq."):
				var parts = endpoint.split("game_id=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["game_id"] = value

			print("[SupabaseDB] Using mock select for steward_accounts with filters: ", filters)
			var result = await MockDatabase.mock_select_steward_accounts(filters)
			return {"code": 200, "data": result}

		elif endpoint.contains("/treasury"):
			var filters = {}
			if endpoint.contains("game_id=eq."):
				var parts = endpoint.split("game_id=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["game_id"] = value

			print("[SupabaseDB] Using mock select for treasury with filters: ", filters)
			var result = await MockDatabase.mock_select_treasury(filters)
			return {"code": 200, "data": result}

		elif endpoint.contains("/allowance_records"):
			var filters = {}
			if endpoint.contains("game_id=eq."):
				var parts = endpoint.split("game_id=eq.")
				if parts.size() > 1:
					var value = parts[1].split("&")[0]
					filters["game_id"] = value

			print("[SupabaseDB] Using mock select for allowance_records with filters: ", filters)
			var result = await MockDatabase.mock_select_allowance_records(filters)
			return {"code": 200, "data": result}

	# 非本地模式或非 mock 表，使用 HTTP 请求
	var http = HTTPRequest.new()
	_manager.add_child(http)

	var headers = _build_headers(true)

	# 本地模式使用本地 API 地址（需要移除 /rest/v1/ 前缀）
	var url: String
	if _manager._is_local_mode:
		# 如果 endpoint 已经是完整 URL，直接使用
		if endpoint.begins_with("http"):
			url = endpoint
		else:
			# 本地模式：移除 /rest/v1/ 前缀
			var clean_endpoint = endpoint.replace("/rest/v1/", "/")
			url = GameConfig.LOCAL_API_BASE + clean_endpoint
	else:
		# 云端模式
		if endpoint.begins_with("http"):
			url = endpoint
		else:
			url = GameConfig.SUPABASE_URL + endpoint

	http.request(url, headers, HTTPClient.METHOD_GET)

	var res = await http.request_completed
	return _on_request_completed_async(res[0], res[1], res[2], res[3], http, endpoint)

# ─────────────────────────────────────────
# 数据库：插入（POST）
# ─────────────────────────────────────────
func db_insert(table, data):
	var body = JSON.stringify(data)
	if _manager._is_local_mode:
		# 检查是否是支持的 mock 表
		if table == "maid_relationships":
			print("[SupabaseDB] Using mock insert for maid_relationships")
			return await MockDatabase.mock_insert_maid_relationship(data)
		elif table == "notifications":
			print("[SupabaseDB] Using mock insert for notifications")
			return await MockDatabase.mock_insert_notification(data)
		elif table == "steward_accounts":
			print("[SupabaseDB] Using mock insert for steward_accounts")
			return await MockDatabase.mock_insert_steward_accounts(data)
		elif table == "allowance_records":
			print("[SupabaseDB] Using mock insert for allowance_records")
			return await MockDatabase.mock_insert_allowance_records(data)
		# 本地模式：使用 pgREST（无 /rest/v1/ 前缀）
		var url = GameConfig.LOCAL_API_BASE + "/" + table
		print("[SupabaseDB] db_insert (local mode): table=", table, ", url=", url)
		return await _post(url, body, false)
	else:
		# 云端模式：使用相对路径
		var endpoint = "/rest/v1/" + table
		print("[SupabaseDB] db_insert (cloud mode): table=", table, ", endpoint=", endpoint)
		return await _post(endpoint, body, true)

# ─────────────────────────────────────────
# 数据库：更新（PATCH）
# 用法：db_update("players", "id=eq.xxx", {"stamina": 5})
# ─────────────────────────────────────────
func db_update(table, filter, data):
	var body = JSON.stringify(data)
	if _manager._is_local_mode:
		return await _patch(GameConfig.LOCAL_API_BASE + "/" + table + "?" + filter, body)
	else:
		return await _patch("/rest/v1/" + table + "?" + filter, body)

# ─────────────────────────────────────────
# 数据库：删除（DELETE）
# 用法：db_delete("players", "id=eq.xxx")
# ─────────────────────────────────────────
func db_delete(table, filter):
	if _manager._is_local_mode:
		return await _delete(GameConfig.LOCAL_API_BASE + "/" + table + "?" + filter)
	else:
		return await _delete("/rest/v1/" + table + "?" + filter)

# ─────────────────────────────────────────
# 数据库：RPC（POST to /rpc/）
# ─────────────────────────────────────────
func db_rpc(function_name: String, params: Dictionary = {}, with_auth: bool = true):
	if _manager._is_local_mode:
		# 本地模式：直接使用 MockDatabase 模拟 RPC
		return await MockDatabase.db_rpc(function_name, params, with_auth)
	else:
		# 云端模式：调用真实 API
		var body = JSON.stringify(params)
		return await _post("/rest/v1/rpc/" + function_name, body, with_auth)

# ─────────────────────────────────────────
# 内部：构建请求头
# ─────────────────────────────────────────
func _build_headers(with_auth):
	var headers = PackedStringArray([
		"Content-Type: application/json",
		"Prefer: return=representation"   # 插入/更新后返回结果
	])

	# 本地模式使用简化的认证头
	if _manager._is_local_mode:
		# 本地模式：使用 Prefer 头跳过认证检查，同时设置简单的 apikey
		headers.append("apikey: local-dev-key")
		headers.append("Prefer: return=representation,merge-duplicates")
	else:
		# 云端模式：使用 Supabase 标准认证
		headers.append("apikey: " + GameConfig.SUPABASE_ANON_KEY)
		if with_auth and _manager.access_token != "":
			headers.append("Authorization: Bearer " + _manager.access_token)

	return headers

func _post(endpoint_or_url, body, with_auth):
	var http = HTTPRequest.new()
	_manager.add_child(http)
	var headers = _build_headers(with_auth)
	var url = endpoint_or_url if endpoint_or_url.begins_with("http") else GameConfig.SUPABASE_URL + endpoint_or_url
	http.request(url, headers, HTTPClient.METHOD_POST, body)

	var res = await http.request_completed
	return _on_request_completed_async(res[0], res[1], res[2], res[3], http, endpoint_or_url)

func _patch(endpoint_or_url, body):
	var http = HTTPRequest.new()
	_manager.add_child(http)
	var headers = _build_headers(true)
	var url = endpoint_or_url if endpoint_or_url.begins_with("http") else GameConfig.SUPABASE_URL + endpoint_or_url
	http.request(url, headers, HTTPClient.METHOD_PATCH, body)

	var res = await http.request_completed
	return _on_request_completed_async(res[0], res[1], res[2], res[3], http, endpoint_or_url)

func _delete(endpoint_or_url):
	var http = HTTPRequest.new()
	_manager.add_child(http)
	var headers = _build_headers(true)
	var url = endpoint_or_url if endpoint_or_url.begins_with("http") else GameConfig.SUPABASE_URL + endpoint_or_url
	http.request(url, headers, HTTPClient.METHOD_DELETE)

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
# Edge Functions：调用
# ─────────────────────────────────────────
func invoke_function(function_name: String, payload: Dictionary = {}):
	var body = JSON.stringify(payload)
	var url = GameConfig.SUPABASE_URL + "/functions/v1/" + function_name
	var res = await _post(url, body, true)
	return res["data"] if res["code"] == 200 else {"success": false, "error": res.get("error", "Unknown error")}

# ─────────────────────────────────────────
# 数据库：查询封装（为了兼容用户代码中的 .query）
# ─────────────────────────────────────────
func query(table_name: String, filters: Dictionary = {}):
	var endpoint = "/rest/v1/" + table_name + "?select=*"
	for key in filters.keys():
		endpoint += "&" + key + "=eq." + str(filters[key])

	var res = await db_get(endpoint)
	return res["data"] if res["code"] == 200 else []

# ─────────────────────────────────────────
# 内部：统一响应处理
# ─────────────────────────────────────────
func _on_request_completed_async(result, response_code, _headers, body, http, endpoint: String = ""):
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		var net_err = "网络连接失败 (Result: %d)" % result
		push_error("[SupabaseDB] " + net_err)

		# 如果是认证相关的请求报错，单独发 auth_error
		if endpoint.contains("/auth/v1/"):
			if _manager.has_signal("auth_error"):
				_manager.emit_signal("auth_error", net_err)

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

		push_error("[SupabaseDB Error %d] %s" % [response_code, err_msg])

		# 如果是认证相关的请求报错，单独发 auth_error
		if endpoint.contains("/auth/v1/"):
			if _manager.has_signal("auth_error"):
				_manager.emit_signal("auth_error", err_msg)

		request_failed.emit(endpoint, err_msg)
		return {"code": response_code, "data": parsed, "error": err_msg}

	# 登录/注册成功：缓存 token（写入 Manager）
	if parsed is Dictionary and (parsed.has("access_token") or parsed.has("email")):
		if parsed.has("access_token"):
			_manager.access_token = str(parsed.get("access_token", ""))
			_manager.refresh_token = str(parsed.get("refresh_token", ""))

		var user_data = parsed.get("user", parsed)
		if user_data is Dictionary:
			_manager.current_uid = str(user_data.get("id", ""))
			if _manager.last_username == "":
				_manager.last_username = str(user_data.get("email", "")).split("@")[0]

		if _manager.has_signal("auth_success"):
			_manager.emit_signal("auth_success", _manager.current_uid)

	var response = {"code": response_code, "data": parsed}
	request_completed.emit(endpoint, response_code, parsed)

	# 登录成功后自动连接实时更新
	if parsed is Dictionary and parsed.has("access_token"):
		if _manager.has_method("_connect_realtime"):
			_manager._connect_realtime()

	return response
