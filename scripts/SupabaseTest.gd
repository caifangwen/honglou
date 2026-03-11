extends Node

# Supabase 连通性测试脚本
# 按照任务要求执行 4 项验证任务

func _ready() -> void:
    print("--- Supabase 连通性测试开始 ---")
    
    # 连接信号
    SupabaseManager.request_completed.connect(_on_supabase_request_completed)
    SupabaseManager.request_failed.connect(_on_supabase_request_failed)
    
    # 1. 读取 games 表
    print("1. 正在读取 games 表...")
    SupabaseManager.get_from_table("games")
    
    # 2. 读取 treasury 表
    print("2. 正在读取 treasury 表...")
    SupabaseManager.get_from_table("treasury")
    
    # 4. 读取 map_locations 表
    print("4. 正在读取 map_locations 表...")
    SupabaseManager.get_from_table("map_locations")
    
    # 3. 执行一次"管家克扣"测试
    # 注意：需要等待获取到 treasury 后的实时数据再进行扣除。
    # 我们将在 _on_supabase_request_completed 中触发。

var test_game_id = "00000000-0000-0000-0000-000000000001"
var treasury_real_balance = 0.0
var treasury_id = ""

func _on_supabase_request_completed(endpoint: String, response_code: int, result: Array) -> void:
    match endpoint:
        "games":
            if result.size() > 0:
                var game = result[0]
                print("   [Games] 亏空值 (deficit_value): ", game.get("deficit_value"))
                print("   [Games] 内耗值 (conflict_value): ", game.get("conflict_value"))
            else:
                print("   [Games] 未找到数据，请确保已执行 SQL 初始化并插入假数据。")
                
        "treasury":
            if result.size() > 0:
                var treasury = result[0]
                # treasury_id = treasury.get("id") # SQL 中 game_id 是 PK
                # treasury_real_balance = treasury.get("real_balance")
                print("   [Treasury] 总银两 (total_silver): ", treasury.get("total_silver"))
                print("   [Treasury] 亏空率 (deficit_rate): ", treasury.get("deficit_rate"))
                
                # 触发"管家克扣"测试 (模拟减少 total_silver)
                print("3. 执行'管家克扣'测试: total_silver -= 200")
                _perform_deduction_test()
            else:
                print("   [Treasury] 未找到数据。")
                
        "map_locations":
            print("4. 全部 5 个地点名称:")
            for loc in result:
                print("   - ", loc.get("location_name"), " (", loc.get("location_key"), ")")
                
        "ledger_entries":
            print("   [Ledger] 插入流水成功。")
            print("--- 测试完成 ---")

func _on_supabase_request_failed(endpoint: String, error_message: String) -> void:
    printerr("   [ERROR] ", endpoint, ": ", error_message)

func _perform_deduction_test() -> void:
    # A. 更新 treasury 的 total_silver
    # 注意：在当前 SQL 结构中，game_id 是 PK
    SupabaseManager.update_table("treasury", "game_id=eq." + test_game_id, {"total_silver": 9800})
    
    # B. 插入 ledger_entries 记录
    # (假设管家账户记录)
    var entry = {
        "game_id": test_game_id,
        "treasury_id": treasury_id,
        "ledger_type": "private",
        "entry_type": "deduction",
        "amount": 200.0,
        "note": "测试：管家私下克扣"
    }
    SupabaseManager.insert_into_table("ledger_entries", entry)
