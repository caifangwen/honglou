# 本地 Mock 数据库完整修复指南

## 修复内容总结

本次修复为本地 Mock 数据库添加了完整的表查询和 RPC 函数支持，现在无需执行任何 SQL 脚本即可测试所有功能。

## 已添加的 Mock 表支持

### 1. players 表
- **查询**: `mock_select_players(filters)`
- **初始化数据**: 15 个测试角色（2 管家 + 6 主子 + 5 丫鬟 + 2 小厮）
- **支持过滤**: current_game_id, auth_uid, id, role_class

### 2. steward_accounts 表
- **查询**: `mock_select_steward_accounts(filters)`
- **插入**: `mock_insert_steward_accounts(data)`
- **自动创建**: 查询时如果没有数据会自动创建默认管家账本

### 3. treasury 表
- **查询**: `mock_select_treasury(filters)`
- **默认数据**: 总银两 50000，繁荣度 Lv.8

### 4. allowance_records 表
- **查询**: `mock_select_allowance_records(filters)`
- **插入**: `mock_insert_allowance_records(data)`
- **记录**: 月例发放历史记录

## 已添加的 Mock RPC 函数

### 1. distribute_allowance_rpc
- **功能**: 发放月例给单个玩家
- **参数**: p_steward_uid, p_recipient_uid, p_recipient_name, p_actual_amount, p_standard_amount, p_game_id
- **返回**: success, withheld, new_deficit

### 2. bulk_distribute_allowance_rpc
- **功能**: 批量发放月例
- **参数**: p_steward_uid, p_game_id, p_distributions (数组)
- **返回**: success, total_withheld, success_count

### 3. get_treasury_stats
- **功能**: 获取银库统计数据
- **参数**: p_game_id
- **返回**: sum_public, sum_withheld

### 4. steward_assign_task
- **功能**: 分派差事
- **参数**: p_target_uid, p_silver_reward, p_task_type
- **支持差事类型**:
  - errand (跑腿): 精力 -2, 基础赏银 5
  - guard (看守): 精力 -1, 基础赏银 8
  - purchase (采办): 精力 -3, 基础赏银 10
  - message (传话): 精力 -2, 基础赏银 6
  - clean (打扫): 精力 -2, 基础赏银 4
  - special (特殊): 精力 -4, 基础赏银 15

### 5. 其他 RPC 函数
- steward_procure_goods
- steward_search_players
- steward_advance_credit
- steward_suppress_rumor
- steward_block_intel

## 测试步骤

### 1. 启动游戏
无需执行任何 SQL 脚本，Mock 数据库会自动初始化。

### 2. 登录测试账号
在登录界面点击快捷登录按钮：
- 🔸 王熙凤 (管家) - 推荐用于测试银库功能
- 👑 贾宝玉 (主子)
- 🌸 袭人 (丫鬟)
- 📦 茗烟 (小厮)

### 3. 测试月例发放
1. 登录王熙凤账号
2. 进入银库界面
3. 应该看到 15 个玩家的列表
4. 点击任意玩家的"发放"按钮
5. 查看控制台日志确认发放成功

### 4. 测试差事分派
1. 在银库界面点击"差使分派"按钮
2. 选择差事类型
3. 选择目标玩家
4. 设置赏银
5. 点击"确认分派"

### 5. 验证数据
切换到被分派差事的玩家账号，检查：
- 银两是否增加
- 精力是否减少

## 控制台日志示例

成功启动后应该看到：

```
[MockDatabase] Initialized
[MockDatabase] mock_select_players - filters: {current_game_id: 00000000-...}
[MockDatabase] Total players in mock: 15
[MockDatabase] Filtered players count: 15
[TreasuryUI] Loading player list for game_id: 00000000-0000-0000-0000-000000000001
[TreasuryUI] Query result code: 200, data count: 15
[TreasuryUI] Final player_list child count: 15
```

点击发放按钮后：

```
[MockDatabase] RPC called: distribute_allowance_rpc with params: {...}
[MockDatabase] Distributed allowance: 贾宝玉 actual=20 withheld=0
[MockDatabase] Bulk distributed allowance: count=1, total_withheld=0
```

点击差使分派后：

```
[MockDatabase] RPC called: steward_assign_task with params: {...}
[MockDatabase] Assigned task: target=22222222-... type=errand reward=10
```

## 故障排查

### 问题 1: 玩家列表为空
**检查日志**: `[MockDatabase] Total players in mock: 0`
**解决**: 确认 `_init_mock_data()` 被调用，检查 `_mock_players.is_empty()` 条件

### 问题 2: RPC 函数未找到
**检查日志**: `[MockDatabase] Unknown RPC function: xxx`
**解决**: 确认 RPC 函数名拼写正确，已在 `db_rpc` 的 match 语句中注册

### 问题 3: 数据未保存
**原因**: Mock 数据存储在内存中，重启游戏后会重置
**解决**: 这是正常行为，如需持久化请使用真实数据库

## 文件修改清单

```
services/supabase/MockDatabase.gd    - 添加所有 mock 方法
services/supabase/SupabaseDB.gd      - 添加本地模式路由
docs/mock_database_fix.md            - 本文档
```

## 下一步

如果所有功能测试通过，可以考虑：
1. 添加更多测试角色
2. 实现数据持久化（保存到本地文件）
3. 添加更多 RPC 函数模拟
4. 集成真实的 Supabase 数据库
