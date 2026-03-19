# 差事分配列表调试指南

## 问题诊断步骤

### 1. 检查数据库中的玩家数据

在 Supabase SQL Editor 中执行：

```sql
-- 查看所有测试角色
SELECT id, character_name, role_class, current_game_id, silver, stamina 
FROM public.players 
WHERE current_game_id = '00000000-0000-0000-0000-000000000001'
ORDER BY 
    CASE role_class 
        WHEN 'steward' THEN 1 
        WHEN 'master' THEN 2 
        WHEN 'servant' THEN 3 
        ELSE 4 
    END;

-- 如果没有数据，执行导入脚本
-- 复制并执行 supabase/sql/import_test_characters.sql 的内容
```

### 2. 运行游戏并查看控制台输出

启动游戏后，打开银库界面，应该看到以下日志：

```
[TreasuryUI] Loading player list for game_id: 00000000-0000-0000-0000-000000000001
[TreasuryUI] player_list has X children
[TreasuryUI] Adding target: 贾宝玉 (master) - id: 22222222-...
[TreasuryUI] Adding target: 林黛玉 (master) - id: 33333333-...
...
```

### 3. 点击"差使分派"按钮

应该看到：

```
[TreasuryUI] _update_task_panel_ui called
[TreasuryUI] player_list has X children
[TreasuryUI] Adding target: 贾宝玉 (主子) - id: 22222222-...
...
```

### 4. 常见错误及解决方案

#### 错误 1: `task_type_selector is null`
**原因**: Treasury.tscn 中 AssignTaskPanel 的节点路径错误
**解决**: 检查场景文件中 TaskTypeSelector 的路径是否为 `AssignTaskPanel/VBoxContainer/TaskTypeSelector`

#### 错误 2: `player_list is null`
**原因**: AllocationPanel/PlayerAllocationList/PlayerAllocationVBox 节点不存在
**解决**: 检查 Treasury.tscn 中玩家列表容器的路径

#### 错误 3: 玩家列表为空
**原因**: 数据库中没有玩家数据或 game_id 不匹配
**解决**: 
1. 执行 import_test_characters.sql 导入测试数据
2. 检查 GameState.current_game_id 是否为 `00000000-0000-0000-0000-000000000001`

#### 错误 4: 差事面板打开后目标选择器为空
**原因**: _load_player_allocation_list() 的异步操作未完成
**解决**: 已修复，_on_AssignTaskBtn_pressed() 现在会 await 玩家列表加载

### 5. 手动测试差事分派

1. 登录王熙凤账号（管家）
2. 进入银库界面
3. 点击"差使分派"按钮
4. 选择差事类型（如"跑腿差事"）
5. 选择目标玩家（如"贾宝玉"）
6. 调整赏银（如 10 两）
7. 点击"确认分派"

### 6. 验证差事结果

切换到被分派的玩家账号（如贾宝玉），检查：
- 银两是否增加
- 精力是否减少
- 是否收到差事消息

## 快速修复命令

如果差事列表仍然不显示，尝试以下命令重置：

```bash
# 1. 重置本地数据库
supabase db reset

# 2. 重新导入测试数据
# 在 Supabase SQL Editor 中执行 import_test_characters.sql

# 3. 重启游戏
```

## 节点路径检查清单

确保 Treasury.tscn 中存在以下节点路径：

```
Treasury (根节点)
├── Header
├── TabContainer
├── AllocationPanel
│   └── PlayerAllocationList
│       └── PlayerAllocationVBox (player_list)
├── ActionPanel
│   ├── AssignTaskBtn
│   └── ...
├── AssignTaskPanel (visible=false)
│   └── VBoxContainer
│       ├── Title
│       ├── TaskTypeLabel
│       ├── TaskTypeSelector (@onready)
│       ├── TargetLabel
│       ├── TaskTargetSelector (@onready)
│       ├── RewardLabel
│       ├── RewardInput (@onready)
│       └── ButtonHBox
│           ├── ConfirmBtn (@onready)
│           └── CancelBtn (@onready)
└── AccountPopup
```

## 代码检查清单

TreasuryUI.gd 中的 @onready 变量：

```gdscript
@onready var task_type_selector: OptionButton = get_node_or_null("AssignTaskPanel/VBoxContainer/TaskTypeSelector")
@onready var task_target_selector: OptionButton = get_node_or_null("AssignTaskPanel/VBoxContainer/TaskTargetSelector")
@onready var task_reward_input: SpinBox = get_node_or_null("AssignTaskPanel/VBoxContainer/RewardInput")
@onready var task_confirm_btn: Button = get_node_or_null("AssignTaskPanel/VBoxContainer/ConfirmBtn")
@onready var task_cancel_btn: Button = get_node_or_null("AssignTaskPanel/VBoxContainer/CancelBtn")
@onready var assign_task_panel: PanelContainer = get_node_or_null("AssignTaskPanel")
```
