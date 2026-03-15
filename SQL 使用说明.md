# SQL 文件使用说明

## 文件结构

```
红楼回忆志/
├── schema.sql          # 数据库架构文件（表结构、索引、函数、RLS 策略）
└── seed.sql            # 种子数据文件（测试账号、初始数据）
```

## 使用顺序

**重要：必须先执行 schema.sql，再执行 seed.sql**

### 1. 执行 schema.sql

在 Supabase SQL Editor 中：
1. 打开 SQL Editor
2. 复制 `schema.sql` 全部内容
3. 粘贴并执行
4. 确认所有表、索引、函数创建成功

### 2. 执行 seed.sql

在 Supabase SQL Editor 中：
1. 打开 SQL Editor
2. 复制 `seed.sql` 全部内容
3. 粘贴并执行
4. 确认测试账号创建成功

## 测试账号

执行 seed.sql 后，将创建以下测试账号（密码均为 `123456`）：

| 邮箱 | 角色 | 扮演人物 | 银两 | 私产 |
|------|------|----------|------|------|
| fengjie@example.com | 管家 (steward) | 凤姐 | 100 | 500 |
| baoyu@test.com | 主子 (master) | 贾宝玉 | 50 | 0 |
| daiyu@test.com | 主子 (master) | 林黛玉 | 30 | 0 |
| xiren@example.com | 丫鬟 (servant) | 袭人 | 10 | 0 |
| qingwen@example.com | 丫鬟 (servant) | 晴雯 | 5 | 0 |

## 主要表结构

### 核心系统
- `games` - 游戏局表
- `players` - 玩家表
- `treasury` - 银库表
- `steward_accounts` - 管家账本表
- `ledger_entries` - 账本条目表

### 流言系统
- `rumors` - 流言表
- `messages` - 消息表

### 听壁脚系统
- `eavesdrop_sessions` - 挂机监听会话表
- `intel_fragments` - 情报碎片表
- `intel_trades` - 情报交易表
- `intel_intercepts` - 情报拦截表（管家专属）

### 社交系统
- `relationships` - 核心关系网表
- `maid_relationships` - 丫鬟关系表
- `servant_relationships` - 丫鬟关系申请表

## 听壁脚系统说明

### 场景列表
- `yi_hong_yuan` - 怡红院后窗
- `treasury_back` - 管家后账房
- `bridge` - 蜂腰桥
- `gate` - 荣国府大门
- `elder_room` - 贾母处

### 情报类型
- `account_leak` - 账目泄露
- `private_action` - 私密行动
- `gift_record` - 馈赠记录
- `visitor_info` - 访客信息
- `elder_favor` - 长辈青睐

### 辅助函数
- `get_scene_listener_count(game_id, scene_key)` - 获取场景监听人数
- `get_session_remaining_time(session_id)` - 获取会话剩余时间
- `is_player_intercepted(player_uid)` - 检查玩家是否被拦截

## 常见问题

### Q: 提示"scene_key 列不存在"
A: 确保已执行最新的 schema.sql，该文件已包含 scene_key 列。

### Q: 提示"表不存在"
A: 请先执行 schema.sql 创建表结构，再执行 seed.sql。

### Q: 测试账号无法登录
A: 确保密码为 `123456`，并检查 auth.users 表是否正确插入数据。

## 清理数据

如需重置数据库，执行：

```sql
-- 删除所有测试数据
DELETE FROM public.intel_intercepts;
DELETE FROM public.intel_trades;
DELETE FROM public.intel_fragments;
DELETE FROM public.eavesdrop_sessions;
DELETE FROM public.maid_relationships;
DELETE FROM public.steward_accounts;
DELETE FROM public.ledger_entries;
DELETE FROM public.messages;
DELETE FROM public.rumors;
DELETE FROM public.players WHERE auth_uid IN (SELECT id FROM auth.users WHERE email LIKE '%@%.com');
DELETE FROM auth.users WHERE email LIKE '%@%.com';
```

然后重新执行 seed.sql。
