extends Node

# InboxManager.gd
# 负责信箱数据的拉取、发送、实时更新及业务规则校验

signal inbox_loaded(messages: Array)
signal new_message_received(message: Dictionary)
signal rumor_updated(rumor: Dictionary)

# 1. 加载信箱（按 tab 分类）
func load_inbox(tab: String = "all") -> Array:
    # tab 可选值: "all" / "private" / "batch_order" / "rumor" / "system"
    var uid = PlayerState.player_db_id
    var game_id = PlayerState.current_game_id
    
    if uid == "" or game_id == "":
        return []
    
    # 获取消息（受 RLS 保护，玩家只能看到自己有权看到的）
    # 同时在查询中显式指定接收者为当前玩家，并关联发送者信息
    var endpoint = "/rest/v1/messages?game_id=eq.%s&receiver_uid=eq.%s&select=*,sender:sender_uid(character_name,display_name)&order=created_at.desc" % [game_id, uid]
    
    # 根据 tab 过滤类型
    if tab != "all":
        endpoint += "&message_type=eq.%s" % tab
    
    var response = await SupabaseManager.db_get(endpoint)
    if response["code"] != 200:
        push_error("[InboxManager] 加载信箱失败: " + str(response))
        return []
    
    var messages = response["data"]
    inbox_loaded.emit(messages)
    return messages

# 2. 发送私信
func send_private_message(receiver_uid: String, content: String, attachments: Array = []) -> Dictionary:
    # 检查精力是否足够（私信消耗1点精力）
    if not PlayerState.consume_stamina(1):
        return {"success": false, "error": "精力不足，无法发送帖子。"}
    
    # 检查接收者是否被管家"封锁消息"
    var is_blocked = await _check_if_blocked(receiver_uid)
    if is_blocked:
        PlayerState.stamina += 1 # 回滚精力
        return {"success": false, "error": "对方已被管家封锁消息，目前无法接收。"}
    
    var msg_data = {
        "game_id": PlayerState.current_game_id,
        "sender_uid": PlayerState.player_db_id,
        "receiver_uid": receiver_uid,
        "message_type": "private",
        "content": content,
        "attachments": attachments,
        "stamina_cost": 1,
        "is_read": false,
        "created_at": Time.get_datetime_string_from_system(false, true)
    }
    
    var res = await SupabaseManager.db_insert("messages", msg_data)
    if res["code"] == 201 or res["code"] == 200:
        return {"success": true, "data": res["data"]}
    else:
        # 回滚精力
        PlayerState.stamina += 1 
        return {"success": false, "error": "发送失败，请检查网络。"}

# 3. 传话系统（丫鬟专属）
func relay_message(original_message_id: String, receiver_uid: String, tamper: bool, tampered_content: String = "") -> Dictionary:
    if PlayerState.role_class != "servant":
        return {"success": false, "error": "只有丫鬟/小厮可进行传话。"}
    
    # 检查声名狼藉状态
    if await _is_notorious(PlayerState.player_db_id):
         return {"success": false, "error": "你已声名狼藉，主子不愿让你传话。"}

    var original_msg = await _get_message_by_id(original_message_id)
    if original_msg.is_empty():
        return {"success": false, "error": "找不到原始消息。"}

    var msg_data = {
        "game_id": PlayerState.current_game_id,
        "sender_uid": PlayerState.player_db_id, # 丫鬟作为中间人发送
        "receiver_uid": receiver_uid,
        "message_type": "private",
        "content": tampered_content if tamper else original_msg["content"],
        "is_tampered": tamper,
        "original_content": original_msg["content"] if tamper else null,
        "stamina_cost": 0 # 传话通常不消耗丫鬟精力，或消耗很少
    }
    
    var res = await SupabaseManager.db_insert("messages", msg_data)
    return {"success": res["code"] in [200, 201], "data": res["data"]}

# 4. 截留信件（丫鬟专属）
func intercept_message(message_id: String) -> Dictionary:
    if PlayerState.role_class != "servant":
        return {"success": false, "error": "非丫鬟阶层无法截留。"}
    
    # 将 is_intercepted 设为 true
    var res = await SupabaseManager.db_update("messages", "id=eq." + message_id, {"is_intercepted": true})
    if res["code"] == 200:
        # 触发"鸿雁断线"事件：双方关系值清零
        var msg = res["data"][0]
        await RelationshipManager.reset_relationship(msg["sender_uid"], msg["receiver_uid"])
        
        # 将截留的消息放入丫鬟自己的情报背包（此处调用 IntelBagManager 或类似系统）
        # EventBus.emit_signal("intel_intercepted", msg)
        
        return {"success": true, "data": msg}
    return {"success": false, "error": "截留失败。"}

# 5. 发布流言
func post_rumor(target_uid: String, content: String, intel_fragments: Array = []) -> Dictionary:
    # 消耗5点精力
    if not PlayerState.consume_stamina(5):
        return {"success": false, "error": "精力不足，无法散播流言。"}
    
    var stage = 0
    # 若 intel_fragments.size() >= 2，触发"流言嫁接"，stage 初始为1
    if intel_fragments.size() >= 2:
        stage = 1
    
    var expires = Time.get_datetime_dict_from_system()
    # 假设流言 24 小时过期
    var expires_at = Time.get_datetime_string_from_unix_time(Time.get_unix_time_from_system() + 86400)
    
    var msg_data = {
        "game_id": PlayerState.current_game_id,
        "sender_uid": PlayerState.player_db_id,
        "receiver_uid": target_uid, # 流言的目标
        "message_type": "rumor",
        "content": content,
        "attachments": intel_fragments,
        "stage": stage,
        "expires_at": expires_at,
        "stamina_cost": 5
    }
    
    var res = await SupabaseManager.db_insert("messages", msg_data)
    return {"success": res["code"] in [200, 201], "data": res["data"]}

# 6. 压下流言（被目标本人）
func suppress_rumor(rumor_id: String) -> bool:
    var rumor = await _get_message_by_id(rumor_id)
    if rumor.is_empty() or rumor["stage"] > 0:
        return false # 仅在 stage == 0（0-6小时内）可操作
    
    # 消耗10点气数
    if PlayerState.qi_shu < 10:
        return false
        
    PlayerState.qi_shu -= 10
    var res = await SupabaseManager.db_delete("messages", "id=eq." + rumor_id)
    return res["code"] == 204 or res["code"] == 200

# 7. 平息流言（管家专属）
func quell_rumor(rumor_id: String) -> bool:
    if PlayerState.role_class != "steward":
        return false
    
    # 消耗2点管家精力
    if not PlayerState.consume_stamina(2):
        return false
        
    # 将流言标记为已过期
    var now = Time.get_datetime_string_from_system()
    var res = await SupabaseManager.db_update("messages", "id=eq." + rumor_id, {"expires_at": now})
    return res["code"] == 200

# 8. 标记已读
func mark_as_read(message_id: String) -> void:
    var res = await SupabaseManager.db_update("messages", "id=eq." + message_id, {"is_read": true})
    if res["code"] == 200:
        # 同时更新或创建 inbox_status
        var status_data = {
            "player_uid": PlayerState.player_db_id,
            "message_id": message_id,
            "read_at": Time.get_datetime_string_from_system()
        }
        await SupabaseManager.db_insert("inbox_status", status_data)

# 9. 实时订阅（Supabase Realtime）
func subscribe_to_inbox() -> void:
    # 订阅 messages 表中 receiver_uid = 当前玩家 的新增消息
    SupabaseManager.subscribe_to_table("messages")
    
    # 监听 SupabaseManager 的实时更新信号
    if not SupabaseManager.realtime_update.is_connected(_on_realtime_update):
        SupabaseManager.realtime_update.connect(_on_realtime_update)

func _on_realtime_update(table_name: String, data: Dictionary) -> void:
    if table_name != "messages":
        return
        
    var event_type = data.get("type", "")
    var new_data = data.get("record", {})
    
    # 只关注插入事件，且接收者是当前玩家
    if event_type == "INSERT" and new_data.get("receiver_uid") == PlayerState.player_db_id:
        new_message_received.emit(new_data)

# --- 内部辅助函数 ---

func _check_if_blocked(target_uid: String) -> bool:
    # 查询 blocked_players 表（假设存在）
    var res = await SupabaseManager.db_get("/rest/v1/blocked_players?player_uid=eq.%s&select=*" % target_uid)
    if res["code"] == 200 and not res["data"].is_empty():
        # 检查是否过期
        var blocked_until = Time.get_unix_time_from_datetime_string(res["data"][0]["blocked_until"])
        return Time.get_unix_time_from_system() < blocked_until
    return false

func _is_notorious(uid: String) -> bool:
    # 检查丫鬟背叛次数是否 >= 3
    # 假设在 players 表或某个 stats 表中有 betrayal_count
    var res = await SupabaseManager.db_get("/rest/v1/players?auth_uid=eq.%s&select=betrayal_count" % uid)
    if res["code"] == 200 and not res["data"].is_empty():
        return res["data"][0].get("betrayal_count", 0) >= 3
    return false

func _get_message_by_id(id: String) -> Dictionary:
    var res = await SupabaseManager.db_get("/rest/v1/messages?id=eq.%s&select=*" % id)
    if res["code"] == 200 and not res["data"].is_empty():
        return res["data"][0]
    return {}
