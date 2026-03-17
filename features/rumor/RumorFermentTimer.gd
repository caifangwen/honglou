extends Node

# RumorFermentTimer.gd
# 负责流言发酵状态的后台同步和到期检查

var check_interval: float = 300.0 # 每5分钟检查一次
var _timer: float = 0.0

func _process(delta: float) -> void:
    _timer += delta
    if _timer >= check_interval:
        _timer = 0.0
        _check_rumors()

func _check_rumors() -> void:
    var game_id = PlayerState.current_game_id
    if game_id == "": return
    
    # 获取所有未到期的流言
    var now = Time.get_datetime_string_from_system()
    var endpoint = "/rest/v1/messages?game_id=eq.%s&message_type=eq.rumor&expires_at=gt.%s&select=*" % [game_id, now]
    
    var res = await SupabaseManager.db_get(endpoint)
    if res["code"] == 200:
        for rumor in res["data"]:
            _update_stage(rumor)

func _update_stage(rumor: Dictionary) -> void:
    var created_at = Time.get_unix_time_from_datetime_string(rumor["created_at"])
    var now = Time.get_unix_time_from_system()
    var elapsed_hours = (now - created_at) / 3600.0
    
    var current_stage = rumor["stage"]
    var new_stage = current_stage
    
    # 规则：0-6h (stage 0), 6-12h (stage 1), 12h+ (stage 2)
    if elapsed_hours >= 12 and current_stage < 2:
        new_stage = 2
    elif elapsed_hours >= 6 and current_stage < 1:
        new_stage = 1
        
    if new_stage != current_stage:
        # 更新数据库
        await SupabaseManager.db_update("messages", "id=eq." + rumor["id"], {"stage": new_stage})
        # 发出实时通知或通过 EventBus
        # EventBus.emit_signal("rumor_stage_changed", rumor["id"], new_stage)
        
        # 如果是 12 小时到期，触发实质处罚
        if new_stage == 2:
            _trigger_rumor_penalty(rumor)

func _trigger_rumor_penalty(rumor: Dictionary) -> void:
    # 调用 Edge Function 或 RPC 执行流言到期后的属性扣除（如体面、气数）
    # 这里的业务逻辑通常在后端执行以保证安全性
    # SupabaseManager.db_rpc("process_rumor_penalty", {"p_rumor_id": rumor["id"]})
    pass
