extends Node

# RelationshipManager.gd (Autoload 单例)
# 管理丫鬟/小厮之间的对食、私约关系，以及弃主投靠逻辑

# 发起对食/私约申请
func send_relation_request(player_uid: String, target_uid: String, relation_type: String) -> bool:
    # relation_type: "dui_shi" 或 "si_yue"
    
    # 1. 验证：双方都是丫鬟/小厮阶层
    # 这里假设我们能从数据库获取目标角色的 role_class
    var target_res = await SupabaseManager.db_get("/rest/v1/players?id=eq." + target_uid + "&select=role_class")
    if target_res["code"] != 200 or target_res["data"].is_empty():
        EventBus.show_notification.emit("无法找到目标角色信息")
        return false
        
    var target_role = target_res["data"][0].get("role_class", "")
    if PlayerState.role_class != "servant" or target_role != "servant":
        EventBus.show_notification.emit("只有丫鬟/小厮阶层可以发起此申请")
        return false
        
    # 2. 验证：双方都没有现有有效关系（一次只能有一段对食关系）
    var check_query = "/rest/v1/maid_relationships?or=(player_a_uid.eq.%s,player_b_uid.eq.%s)&status=in.(pending,active)&select=id" % [player_uid, player_uid]
    var player_rel_res = await SupabaseManager.db_get(check_query)
    if not player_rel_res["data"].is_empty():
        EventBus.show_notification.emit("你当前已有正在进行或待确认的关系")
        return false
        
    var target_check_query = "/rest/v1/maid_relationships?or=(player_a_uid.eq.%s,player_b_uid.eq.%s)&status=in.(pending,active)&select=id" % [target_uid, target_uid]
    var target_rel_res = await SupabaseManager.db_get(target_check_query)
    if not target_rel_res["data"].is_empty():
        EventBus.show_notification.emit("目标当前已有正在进行或待确认的关系")
        return false
        
    # 3. 写入 maid_relationships 表（status="pending"，等待对方确认）
    var insert_data = {
        "player_a_uid": player_uid,
        "player_b_uid": target_uid,
        "relation_type": relation_type,
        "status": "pending",
        "shared_intel_ids": []
    }
    var insert_res = await SupabaseManager.db_insert("maid_relationships", insert_data)
    if insert_res["code"] != 201:
        EventBus.show_notification.emit("发送申请失败，请稍后重试")
        return false
        
    # 4. 推送通知给 target_uid (这里通过 EventBus 模拟，实际可能需要后端推送或长连接)
    EventBus.show_notification.emit("已向对方发送关系申请")
    # TODO: 后续可接入 Supabase Realtime 或消息表推送给对方
    
    return true

# 接受关系申请
func accept_relation_request(relationship_id: String) -> bool:
    # 1. 更新 maid_relationships.status = "active", formed_at = now()
    var update_data = {
        "status": "active",
        "formed_at": Time.get_datetime_string_from_system(false, true)
    }
    var update_res = await SupabaseManager.db_update("maid_relationships", "id=eq." + relationship_id, update_data)
    if update_res["code"] != 200:
        EventBus.show_notification.emit("接受申请失败")
        return false
        
    # 2. 双方均可见彼此收集的情报碎片 id 列表（用于背叛时的出卖）
    # 这里逻辑通常在 UI 层展示，或者通过 db 触发器/RPC 处理。
    # 我们这里触发一个信号通知 UI 更新
    EventBus.show_notification.emit("关系已达成，情报获取速率翻倍！")
    EventBus.relation_changed.emit("", "", "active") # 简化处理，仅通知状态改变
    
    return true

# 背叛搭档
func betray_partner(relationship_id: String, betrayer_uid: String) -> void:
    # 1. 获取关系详情
    var rel_res = await SupabaseManager.db_get("/rest/v1/maid_relationships?id=eq." + relationship_id + "&select=*")
    if rel_res["code"] != 200 or rel_res["data"].is_empty():
        return
        
    var rel_data = rel_res["data"][0]
    var shared_intel_ids = rel_data.get("shared_intel_ids", [])
    var partner_uid = rel_data.get("player_a_uid") if rel_data.get("player_b_uid") == betrayer_uid else rel_data.get("player_b_uid")
    
    # 2. 更新 status = "betrayed"，betrayer_uid = 当前玩家
    var update_rel_data = {
        "status": "betrayed",
        "betrayer_uid": betrayer_uid
    }
    await SupabaseManager.db_update("maid_relationships", "id=eq." + relationship_id, update_rel_data)
    
    # 3. 将 shared_intel_ids 列表中的所有碎片，给被背叛方一份副本（相同情报碎片）
    # 假设有一个 intel_fragments 表，我们需要为 partner_uid 插入副本
    # 这里通过 RPC 调用后端逻辑更安全，或者批量插入
    if not shared_intel_ids.is_empty():
        for intel_id in shared_intel_ids:
            var intel_res = await SupabaseManager.db_get("/rest/v1/intel_fragments?id=eq." + intel_id + "&select=*")
            if intel_res["code"] == 200 and not intel_res["data"].is_empty():
                var original_intel = intel_res["data"][0]
                var copy_intel = original_intel.duplicate()
                copy_intel.erase("id") # 移除旧 ID 让 Supabase 生成新 ID
                copy_intel["player_uid"] = partner_uid
                copy_intel["is_copy"] = true
                await SupabaseManager.db_insert("intel_fragments", copy_intel)
                
    # 4. 被背叛方收到通知
    var betrayal_msg = "[%s] 背叛了你们的私约，你获得了所有共同情报的副本" % PlayerState.character_name
    await SupabaseManager.db_insert("notifications", {
        "player_uid": partner_uid,
        "content": betrayal_msg,
        "type": "betrayal",
        "created_at": Time.get_datetime_string_from_system(false, true)
    })
    
    # 5. 背叛方 maid_loyalty 中 abandon_count + 1
    # 先获取当前记录
    var loyalty_res = await SupabaseManager.db_get("/rest/v1/maid_loyalty?maid_uid=eq." + betrayer_uid + "&select=*")
    if loyalty_res["code"] == 200 and not loyalty_res["data"].is_empty():
        var l_data = loyalty_res["data"][0]
        var new_abandon_count = l_data.get("abandon_count", 0) + 1
        await SupabaseManager.db_update("maid_loyalty", "id=eq." + str(l_data["id"]), {"abandon_count": new_abandon_count})
        
        # 6. 检查"声名狼藉"状态
        await check_disgrace(betrayer_uid)
        
    # 7. 背叛方体面值 - 10
    PlayerState.face_value -= 10
    # 同步到数据库
    await SupabaseManager.db_update("players", "id=eq." + PlayerState.player_db_id, {"face_value": PlayerState.face_value})
    
    EventBus.show_notification.emit("你背叛了搭档，体面值下降，声望受损")

# 检查"声名狼藉"状态
func check_disgrace(player_uid: String) -> bool:
    var loyalty_res = await SupabaseManager.db_get("/rest/v1/maid_loyalty?maid_uid=eq." + player_uid + "&select=*")
    if loyalty_res["code"] == 200 and not loyalty_res["data"].is_empty():
        var l_data = loyalty_res["data"][0]
        if l_data.get("abandon_count", 0) >= 3:
            await SupabaseManager.db_update("maid_loyalty", "id=eq." + str(l_data["id"]), {"is_disgraced": true})
            return true
    return false

# 弃主投靠（换主子）
func abandon_master(maid_uid: String, old_master_uid: String, new_master_uid: String) -> bool:
    # 1. 检查 is_disgraced：若为true，拒绝新主子接收，返回false
    var loyalty_res = await SupabaseManager.db_get("/rest/v1/maid_loyalty?maid_uid=eq." + maid_uid + "&select=*")
    if loyalty_res["code"] == 200 and not loyalty_res["data"].is_empty():
        if loyalty_res["data"][0].get("is_disgraced", false):
            EventBus.show_notification.emit("你已声名狼藉，没有主子愿意收留你")
            return false
            
    # 2. 更新 maid_loyalty 表：将旧主子记录 loyalty_score = 0，end_relation
    # 假设这里是更新状态或记录结束时间
    await SupabaseManager.db_update("maid_loyalty", "maid_uid=eq.%s&master_uid=eq.%s" % [maid_uid, old_master_uid], {
        "loyalty_score": 0,
        "status": "abandoned",
        "end_at": Time.get_datetime_string_from_system(false, true)
    })
    
    # 3. 为旧主子添加"被背叛标记"（写入事件日志）
    var event_log = {
        "player_uid": old_master_uid,
        "event_type": "maid_betrayal",
        "description": "丫鬟 [%s] 弃你而去，投靠了他人" % PlayerState.character_name,
        "created_at": Time.get_datetime_string_from_system(false, true)
    }
    await SupabaseManager.db_insert("event_logs", event_log)
    
    # 4. 在旧主子的 player_status 表中标记"已被[XXX]丫鬟背叛"
    # 这里假设有一个 player_status 表存储玩家的负面状态或标记
    # 我们先检查是否存在记录
    var status_res = await SupabaseManager.db_get("/rest/v1/player_status?player_uid=eq." + old_master_uid)
    var betrayal_tag = "已被%s背叛" % PlayerState.character_name
    if status_res["code"] == 200 and not status_res["data"].is_empty():
        var tags = status_res["data"][0].get("betrayal_tags", [])
        if not betrayal_tag in tags:
            tags.append(betrayal_tag)
            await SupabaseManager.db_update("player_status", "player_uid=eq." + old_master_uid, {"betrayal_tags": tags})
    else:
        await SupabaseManager.db_insert("player_status", {
            "player_uid": old_master_uid,
            "betrayal_tags": [betrayal_tag]
        })
    
    # 5. 创建新的 maid_loyalty 记录（对新主子，初始50）
    var new_loyalty = {
        "maid_uid": maid_uid,
        "master_uid": new_master_uid,
        "loyalty_score": 50,
        "status": "active",
        "start_at": Time.get_datetime_string_from_system(false, true)
    }
    await SupabaseManager.db_insert("maid_loyalty", new_loyalty)
    
    # 更新本地忠诚度缓存
    PlayerState.loyalty = 50
    
    EventBus.show_notification.emit("你已投靠新主子")
    return true

# 辅助：获取当前玩家的关系
func get_current_relationship(player_uid: String) -> Dictionary:
    var query = "/rest/v1/maid_relationships?or=(player_a_uid.eq.%s,player_b_uid.eq.%s)&status=eq.active&select=*,player_a:player_a_uid(character_name),player_b:player_b_uid(character_name)" % [player_uid, player_uid]
    var res = await SupabaseManager.db_get(query)
    if res["code"] == 200 and not res["data"].is_empty():
        return res["data"][0]
    return {}

# 辅助：获取待确认的申请
func get_pending_requests(player_uid: String) -> Array:
    var query = "/rest/v1/maid_relationships?player_b_uid=eq.%s&status=eq.pending&select=*,player_a:player_a_uid(character_name)" % player_uid
    var res = await SupabaseManager.db_get(query)
    if res["code"] == 200:
        return res["data"]
    return []
