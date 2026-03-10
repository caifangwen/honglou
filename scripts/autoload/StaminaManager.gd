extends Node

# StaminaManager.gd
# 处理管家精力系统的本地计算与同步

signal stamina_updated(new_stamina: int)

func get_current_stamina(uid: String) -> int:
	# 1. 向服务器获取原始数据
	# 使用 SupabaseManager 执行查询
	var endpoint = "/rest/v1/steward_stamina?uid=eq.%s&select=*" % uid
	SupabaseManager.db_get(endpoint)
	
	var response = await SupabaseManager.request_complete
	if response["code"] != 200:
		push_error("[StaminaManager] 获取精力失败: " + str(response))
		return 0
	
	var data = response["data"]
	if data.is_empty():
		return 0
	
	var stamina_info = data[0]
	
	# 2. 本地乐观计算 (基于上次刷新时间)
	var last_refresh_at_str = stamina_info["last_refresh_at"]
	var last_refresh_at = Time.get_unix_time_from_datetime_string(last_refresh_at_str)
	var now = Time.get_unix_time_from_system()
	
	var elapsed_seconds = now - last_refresh_at
	var recovered = int(elapsed_seconds / GameConfig.STAMINA_RECOVERY_SEC)
	
	var current_stamina = min(stamina_info["current_stamina"] + recovered, stamina_info["max_stamina"])
	
	stamina_updated.emit(current_stamina)
	return current_stamina

# 在执行任何行动前，调用 Edge Function 进行最终验证并扣除精力
func execute_steward_action(action_type: String, target_uid: String, params: Dictionary = {}):
	var body = {
		"actor_id": SupabaseManager.current_uid,
		"action_type": action_type,
		"target_uid": target_uid,
		"params": params,
		"game_id": GameState.current_game_id # 假设 GameState 存储当前局ID
	}
	
	# 调用 execute-action Edge Function
	var url = "/functions/v1/execute-action"
	SupabaseManager._post(url, JSON.stringify(body), true)
	
	var response = await SupabaseManager.request_complete
	if response["code"] == 200:
		# 更新本地精力缓存（如果需要）
		get_current_stamina(SupabaseManager.current_uid)
		return {"success": true, "data": response["data"]}
	else:
		return {"success": false, "error": response.get("data", {}).get("error", "未知错误")}
