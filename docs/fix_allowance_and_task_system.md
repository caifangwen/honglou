# 修复月例发放和差事分配问题

## 问题总结

从日志中发现两个问题：
1. **玩家列表不显示** - 需要检查节点路径
2. **缺少 RPC 函数** - `distribute_allowance_rpc` 函数不存在于数据库中

## 修复步骤

### 步骤 1: 执行 SQL 修复脚本

在 Supabase SQL Editor 中执行以下脚本：

```sql
-- 文件：supabase/sql/fix_missing_rpc_functions.sql
```

或者在本地开发环境中：

```bash
# 如果使用本地 Supabase
psql -h localhost -U postgres -d postgres -f supabase/sql/fix_missing_rpc_functions.sql
```

### 步骤 2: 重启游戏并查看日志

启动游戏后，进入银库界面，应该看到以下日志：

```
[TreasuryUI] _ready() called
[TreasuryUI] player_list node: VBoxContainer:xxx
[TreasuryUI] _load_player_allocation_list called
[TreasuryUI] player_list node: VBoxContainer:xxx
[TreasuryUI] Loading player list for game_id: 00000000-0000-0000-0000-000000000001
[TreasuryUI] Query result code: 200, data count: 15
[TreasuryUI] Cleared old list, new child count: 0
[TreasuryUI] Final player_list child count: 15
```

### 步骤 3: 测试月例发放

1. 在银库界面，应该看到 15 个玩家的列表
2. 每个玩家有"应发"、"实际输入"和"发放"按钮
3. 点击"发放"按钮，应该成功发放月例

### 步骤 4: 测试差事分派

1. 点击"差使分派"按钮
2. 应该看到差事分派面板弹出
3. 选择差事类型和目标玩家
4. 点击"确认分派"执行

## 常见问题

### Q1: player_list node is null

**错误日志**:
```
[TreasuryUI] player_list node is null! Check scene path
```

**原因**: Treasury.tscn 中的节点路径错误

**解决**: 检查 Treasury.tscn 中是否有以下节点结构：

```
Treasury (根节点)
└── AllocationPanel
    └── PlayerAllocationList (ScrollContainer)
        └── PlayerAllocationVBox (VBoxContainer) ← player_list
```

如果节点路径不同，需要修改 TreasuryUI.gd 中的 `@onready` 声明：

```gdscript
@onready var player_list: VBoxContainer = get_node_or_null("AllocationPanel/PlayerAllocationList/PlayerAllocationVBox")
```

### Q2: RPC 函数不存在

**错误日志**:
```
Could not find the function public.distribute_allowance_rpc(...)
```

**解决**: 执行 `supabase/sql/fix_missing_rpc_functions.sql` 脚本

### Q3: 玩家列表为空

**原因**: 数据库中没有玩家数据

**解决**: 执行 `supabase/sql/import_test_characters.sql` 导入测试角色

### Q4: 差事面板目标选择器为空

**原因**: 玩家列表未加载完成或 role_class meta 未存储

**解决**: 
1. 确保 `_add_player_to_list` 函数中有：
   ```gdscript
   item.set_meta("role_class", player_info.get("role_class", "servant"))
   ```
2. 点击"差使分派"按钮时会等待玩家列表加载完成

## 文件清单

本次修复涉及的文件：

```
features/treasury/TreasuryUI.gd       - 已添加调试日志
features/treasury/Treasury.tscn       - 检查节点路径
supabase/sql/fix_missing_rpc_functions.sql - 新增 RPC 函数
supabase/sql/import_test_characters.sql    - 测试角色数据
docs/fix_allowance_and_task_system.md      - 本文档
```

## 验证清单

- [ ] 执行 `fix_missing_rpc_functions.sql` 脚本
- [ ] 重启游戏
- [ ] 进入银库界面
- [ ] 看到玩家列表（至少 1 个玩家）
- [ ] 点击"发放"按钮成功发放月例
- [ ] 点击"差使分派"按钮打开面板
- [ ] 选择差事类型和目标玩家
- [ ] 成功执行差事分派

## 下一步

如果以上步骤都完成但问题仍然存在，请提供：
1. 完整的游戏控制台日志
2. Treasury.tscn 文件内容
3. TreasuryUI.gd 文件内容

以便进一步诊断问题。
