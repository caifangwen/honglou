extends Node

# BridgeMarket.gd（集市核心逻辑）
# 实现丫鬟/小厮阶层的异步情报交易

func can_enter() -> bool:
	# 只有丫鬟/小厮阶层可以进入
	return PlayerState.role_class == "servant"

# 挂出出售情报
func list_intel_for_sale(fragment_id: String, price_silver: int, price_qi: int) -> bool:
	if not can_enter():
		push_error("[Market] Only servants can list intel.")
		return false
		
	# 1. 验证：price_silver 和 price_qi 只能设一个（不能同时设置）
	if price_silver > 0 and price_qi > 0:
		push_error("[Market] Silver and Qi cannot be set at the same time.")
		return false
	
	# 2. 验证：情报属于当前玩家，且未被使用/出售
	# 这里假设 owner_uid 是 intel_fragments 表中存储所有者的字段
	var endpoint = "/rest/v1/intel_fragments?id=eq.%s&owner_uid=eq.%s&is_used=eq.false&is_sold=eq.false&select=*" % [fragment_id, PlayerState.uid]
	var res = await SupabaseManager.db_get(endpoint)
	if res["code"] != 200 or res["data"].is_empty():
		push_error("[Market] Intel fragment not found or already sold/used.")
		return false
	
	# 3. 写入 intel_trades 表，status=pending
	var trade_data = {
		"fragment_id": fragment_id,
		"seller_uid": PlayerState.uid,
		"price_silver": price_silver,
		"price_qi": price_qi,
		"status": "pending",
		"game_id": PlayerState.current_game_id
	}
	var trade_res = await SupabaseManager.db_insert("intel_trades", trade_data)
	if trade_res["code"] >= 400:
		return false
	
	# 4. 更新 intel_fragments.is_sold=false（挂出中，尚未完成交易）
	# 虽然原本就是 false，但此处按要求显式设置/确保状态。
	# 在实际业务中，可能需要标记 fragment 为 'listing' 状态以防止重复挂单或被流言系统使用。
	await SupabaseManager.db_update("intel_fragments", "id=eq." + fragment_id, {"is_sold": false})
	
	return true

# 购买情报
func purchase_intel(trade_id: String, buyer_uid: String) -> Dictionary:
	if not can_enter():
		return {"success": false, "error": "只有丫鬟/小厮可以进入集市"}
		
	# 1. 查询 intel_trades，获取价格信息
	var trade_endpoint = "/rest/v1/intel_trades?id=eq.%s&status=eq.pending&select=*" % trade_id
	var trade_res = await SupabaseManager.db_get(trade_endpoint)
	if trade_res["code"] != 200 or trade_res["data"].is_empty():
		return {"success": false, "error": "交易已失效或已被他人购买"}
	
	var trade = trade_res["data"][0]
	var seller_uid = trade["seller_uid"]
	var fragment_id = trade["fragment_id"]
	var p_silver = trade["price_silver"]
	var p_qi = trade["price_qi"]
	
	# 2. 验证买家不是卖家本人
	if seller_uid == buyer_uid:
		return {"success": false, "error": "不能购买自己挂出的情报"}
	
	# 3. 验证买家有足够银两/气数
	if p_silver > 0 and PlayerState.silver < p_silver:
		return {"success": false, "error": "银两不足"}
	if p_qi > 0 and PlayerState.qi_shu < p_qi:
		return {"success": false, "error": "气数不足"}
	
	# 4. 事务性操作（使用 Supabase RPC）：
	# 此 RPC 需要在 Supabase 端定义，处理扣款、加款、所有权转移、交易状态更新
	var rpc_params = {
		"p_trade_id": trade_id,
		"p_buyer_uid": buyer_uid,
		"p_seller_uid": seller_uid,
		"p_fragment_id": fragment_id,
		"p_price_silver": p_silver,
		"p_price_qi": p_qi
	}
	
	var res = await SupabaseManager.db_rpc("purchase_intel_transaction", rpc_params)
	if res["code"] >= 400:
		return {"success": false, "error": "交易执行失败"}
	
	# 交易成功后，刷新买家本地状态
	if p_silver > 0: PlayerState.silver -= p_silver
	if p_qi > 0: PlayerState.qi_shu -= p_qi
	
	# 5. 获取具体情报内容（购买后方可见）
	var frag_res = await SupabaseManager.db_get("/rest/v1/intel_fragments?id=eq.%s&select=*" % fragment_id)
	var fragment = frag_res["data"][0] if not frag_res["data"].is_empty() else {}
	
	return {"success": true, "fragment": fragment}

# 取消挂单
func cancel_listing(trade_id: String) -> bool:
	# 1. 验证当前玩家是卖家
	var res = await SupabaseManager.db_get("/rest/v1/intel_trades?id=eq.%s&status=eq.pending&select=*" % trade_id)
	if res["code"] != 200 or res["data"].is_empty():
		return false
	
	var trade = res["data"][0]
	if trade["seller_uid"] != PlayerState.uid:
		return false
	
	# 2. 更新 intel_trades.status = cancelled
	var update_res = await SupabaseManager.db_update("intel_trades", "id=eq." + trade_id, {"status": "cancelled"})
	return update_res["code"] < 400

# 获取集市列表（不暴露碎片具体内容）
func get_market_listings(game_id: String) -> Array:
	# 查询 intel_trades（status=pending）JOIN intel_fragments
	# 返回字段：trade_id, intel_type, value_level, price_silver, price_qi
	# 注意：不返回 content 字段（防止不买就看内容）
	# Supabase JOIN 查询语法：select=*,intel_fragments(intel_type,value_level,scene)
	var endpoint = "/rest/v1/intel_trades?status=eq.pending&game_id=eq.%s&select=id,price_silver,price_qi,intel_fragments(intel_type,value_level,scene)" % game_id
	var res = await SupabaseManager.db_get(endpoint)
	
	if res["code"] != 200:
		return []
	
	var results = []
	for item in res["data"]:
		var frag = item.get("intel_fragments", {})
		# 如果 frag 是 Array（Supabase 有时返回 array），取第一个
		if frag is Array: frag = frag[0] if not frag.is_empty() else {}
		
		results.append({
			"trade_id": item["id"],
			"intel_type": frag.get("intel_type", "unknown"),
			"value_level": frag.get("value_level", 1),
			"scene": frag.get("scene", "unknown"),
			"price_silver": item["price_silver"],
			"price_qi": item["price_qi"]
		})
	return results
