# 红楼回忆志 - 数据库完整文档

> 最后更新：2026-03-18  
> 版本：2.0

---

## 目录

1. [快速开始](#1-快速开始)
2. [文件结构](#2-文件结构)
3. [环境配置](#3-环境配置)
4. [数据库架构](#4-数据库架构)
5. [核心系统说明](#5-核心系统说明)
6. [RPC 函数参考](#6-rpc 函数参考)
7. [调试指南](#7-调试指南)
8. [常见问题](#8-常见问题)

---

## 1. 快速开始

### 1.1 本地开发环境（推荐）

```powershell
# 1. 启动 Docker 容器
docker compose -f docker-compose.local-dev.yml --project-name honglou up -d

# 2. 等待数据库初始化（首次启动约 30 秒）
docker ps --filter "name=honglou"

# 3. 访问 API 测试
curl http://localhost:3000/players?select=*&limit=1
```

### 1.2 Supabase 云端环境

1. 登录 Supabase Dashboard
2. 打开 SQL Editor
3. 执行 `supabase/sql/full_schema.sql`
4. 执行 `supabase/sql/seed.sql`

---

## 2. 文件结构

```
红楼回忆志/
├── supabase/
│   ├── sql/
│   │   ├── full_schema.sql      # 完整架构文件（推荐使用）
│   │   ├── seed.sql             # 种子数据（测试账号）
│   │   ├── combined_schema.sql  # 旧版架构（已废弃）
│   │   └── schema.sql           # 旧版主 schema（已废弃）
│   └── migrations/              # 历史迁移记录（已合并到 full_schema.sql）
├── docker-compose.local-dev.yml # 本地开发环境配置
└── docs/
    └── DATABASE_GUIDE.md        # 本文档
```

### 2.1 SQL 文件说明

| 文件 | 用途 | 大小 | 推荐使用 |
|------|------|------|----------|
| `full_schema.sql` | 完整架构 + 函数 + 策略 | ~2000 行 | ✅ 是 |
| `seed.sql` | 测试数据 | ~100 行 | ✅ 是 |
| `combined_schema.sql` | 旧版完整架构 | ~1500 行 | ❌ 已废弃 |
| `schema.sql` | 旧版主 schema | ~1000 行 | ❌ 已废弃 |
| `migrations/*.sql` | 历史增量迁移 | 多个文件 | ❌ 已合并 |

---

## 3. 环境配置

### 3.1 本地 Docker 环境

**容器列表**：
- `honglou_local_db` - PostgreSQL 15 数据库
- `honglou_pgrest` - pgREST API 服务（端口 3000）
- `honglou_pgadmin` - 数据库管理界面（端口 5050）

**连接信息**：
```
主机：localhost
端口：5432
数据库：honglou
用户：postgres
密码：postgres123
```

**pgREST API**：
```
URL: http://localhost:3000
Header: apikey: local-dev-key
Header: Prefer: return=representation,merge-duplicates
```

**pgAdmin 登录**：
```
邮箱：admin@admin.com
密码：admin
```

### 3.2 Supabase 云端环境

**连接信息**：
```
项目 URL: https://daotqqwsxvydxqttmams.supabase.co
API Key: 见 .env.local 文件
```

**本地/云端切换**：
在 Godot 项目中通过 `GameConfig.USE_LOCAL_DB` 控制：
- `true` - 使用本地 pgREST API
- `false` - 使用 Supabase 云端

---

## 4. 数据库架构

### 4.1 核心表

#### games - 游戏局表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| status | text | 状态：active, crisis, purge, ended |
| start_timestamp | bigint | 开始时间戳 |
| speed_multiplier | float | 时间流速倍率 |
| deficit_value | float | 亏空值（0-100） |
| conflict_value | float | 内耗值（0-100） |
| current_day | int | 当前天数 |

#### players - 玩家表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| auth_uid | uuid | 认证用户 ID |
| username | text | 用户名 |
| display_name | text | 显示名称 |
| character_name | text | 角色名（如：凤姐） |
| role_class | text | 阶层：steward, master, servant, elder, guest |
| current_game_id | uuid | 当前游戏局 ID |
| stamina | int | 精力值 |
| stamina_max | int | 精力上限 |
| stamina_refreshed_at | timestamptz | 精力刷新时间 |
| silver | int | 银两 |
| private_silver | int | 私产银两 |
| prestige | int | 威望 |

#### treasury - 银库表
| 字段 | 类型 | 说明 |
|------|------|------|
| game_id | uuid | 关联游戏局 |
| total_silver | int | 总银两 |
| public_balance | int | 公中余额 |
| real_balance | int | 实际余额 |
| prosperity_level | int | 繁荣度 |
| deficit_rate | float | 亏空率 |

### 4.2 管家系统表

#### steward_accounts - 管家账本表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| game_id | uuid | 游戏局 ID |
| steward_uid | uuid | 管家玩家 ID |
| public_ledger | jsonb | 公账记录 |
| private_ledger | jsonb | 私账记录 |
| private_assets | int | 私产总额 |
| route | steward_route | 路线：virtuous, schemer |

#### ledger_entries - 账本条目表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| game_id | uuid | 游戏局 ID |
| treasury_id | uuid | 关联银库 |
| actor_id | uuid | 操作者 ID |
| target_id | uuid | 目标玩家 ID |
| ledger_type | text | 账本类型：public, private |
| entry_type | text | 条目类型：allocation, procurement, advance |
| amount | int | 金额 |
| note | text | 备注 |

#### allowance_records - 月例发放记录表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| game_id | uuid | 游戏局 ID |
| player_id | uuid | 领取玩家 ID |
| issued_by | uuid | 发放者 ID |
| amount_public | int | 公中发放金额 |
| amount_actual | int | 实际到手金额 |
| withheld_amount | int | 克扣金额 |
| is_public | boolean | 是否公开 |

#### procurement_tickets - 采办票据表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| game_id | uuid | 游戏局 ID |
| steward_uid | uuid | 管家 ID |
| item_template_key | text | 物品模板键 |
| quantity | int | 数量 |
| status | text | 状态：pending, used, cancelled |

#### action_approvals - 行动批条表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| game_id | uuid | 游戏局 ID |
| steward_uid | uuid | 管家 ID |
| action_type | text | 行动类型 |
| stamina_cost | int | 精力消耗 |
| params | jsonb | 参数 |
| status | text | 状态：pending, executed, cancelled |

### 4.3 流言系统表

#### rumors - 流言表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| game_id | uuid | 游戏局 ID |
| owner_uid | uuid | 所有者 ID |
| source_uid | uuid | 来源 ID |
| target_uid | uuid | 目标 ID |
| content | text | 流言内容 |
| stage | int | 阶段：1-4 |
| spread_count | int | 传播次数 |
| belief_rate | float | 相信率 |
| status | text | 状态：active, suppressed, expired |
| expires_at | timestamptz | 过期时间 |

#### messages - 消息表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| game_id | uuid | 游戏局 ID |
| sender_uid | uuid | 发送者 ID |
| receiver_uid | uuid | 接收者 ID |
| message_type | text | 类型：private, rumor, batch_order, system |
| content | text | 内容 |
| attachments | jsonb | 附件（情报碎片等） |
| stamina_cost | int | 精力消耗 |
| is_tampered | boolean | 是否被篡改 |
| is_intercepted | boolean | 是否被截留 |
| stage | int | 流言阶段 |

### 4.4 听壁脚系统表

#### eavesdrop_sessions - 挂机监听会话表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| game_id | uuid | 游戏局 ID |
| player_uid | uuid | 玩家 ID |
| scene | scene_location | 场景枚举 |
| scene_key | text | 场景键值 |
| partner_uid | uuid | 搭档 ID（双人挂机） |
| is_duo | boolean | 是否双人挂机 |
| ends_at | timestamptz | 结束时间 |
| status | session_status | 状态：active, completed |
| result_count | int | 已生成情报数 |

#### intel_fragments - 情报碎片表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| game_id | uuid | 游戏局 ID |
| owner_uid | uuid | 所有者 ID |
| content | text | 情报内容 |
| intel_type | intel_type | 情报类型枚举 |
| scene | text | 来源场景 |
| value_level | int | 价值等级：1-5 |
| status | text | 状态：unread, read, used |
| is_used | boolean | 是否已使用 |
| is_blocked | boolean | 是否被封锁 |
| blocked_until | timestamptz | 封锁截止时间 |

#### intel_trades - 情报交易表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| seller_uid | uuid | 卖家 ID |
| buyer_uid | uuid | 买家 ID |
| fragment_id | uuid | 情报碎片 ID |
| price_silver | int | 银两价格 |
| status | trade_status | 状态：pending, completed |

#### intel_intercepts - 情报拦截表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| interceptor_uid | uuid | 拦截者 ID |
| target_uid | uuid | 目标 ID |
| starts_at | timestamptz | 开始时间 |
| ends_at | timestamptz | 结束时间 |
| status | text | 状态：active, expired |

### 4.5 社交关系表

#### relationships - 核心关系网表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| game_id | uuid | 游戏局 ID |
| player_a | uuid | 玩家 A ID |
| player_b | uuid | 玩家 B ID |
| relation_type | text | 关系类型：ally, rival, confidant |
| is_mutual | boolean | 是否双向 |

#### maid_relationships - 丫鬟关系表
| 字段 | 类型 | 说明 |
|------|------|------|
| id | uuid | 主键 |
| game_id | uuid | 游戏局 ID |
| player_a_uid | uuid | 玩家 A ID |
| player_b_uid | uuid | 玩家 B ID |
| relation_type | maid_relation_type | 关系：dui_shi, si_yue |
| status | maid_relation_status | 状态：pending, active |

---

## 5. 核心系统说明

### 5.1 精力系统

**恢复机制**：
- 每 2 小时（7200 秒）自动恢复 1 点精力
- 恢复公式：`当前精力 = min(基础精力 + 恢复次数，精力上限)`

**各阶层精力上限**：
| 阶层 | 精力上限 | 来源 |
|------|----------|------|
| 管家 | 6 | GameConfig.STAMINA_STEWARD |
| 主子 | 6 | GameConfig.STAMINA_MASTER |
| 丫鬟/小厮 | 8 | GameConfig.STAMINA_SERVANT |
| 元老 | 6 | GameConfig.STAMINA_ELDER |
| 清客 | 6 | GameConfig.STAMINA_GUEST |

**精力消耗**：
| 行动 | 消耗 | 常量 |
|------|------|--------|
| 采办物资 | 1 | COST_PROCURE |
| 差使分派 | 1 | COST_ASSIGN_TASK |
| 搜检大观园 | 2 | COST_SEARCH_GARDEN |
| 预支批条 | 1 | COST_ADVANCE_PAYMENT |
| 平息流言 | 2 | COST_SUPPRESS_RUMOR |
| 封锁消息 | 3 | COST_BLOCK_INFO |
| 发布流言 | 5 | COST_PUBLISH_RUMOR |
| 听壁脚 | 2 | COST_SEARCH_GARDEN |
| 拦截情报 | 3 | COST_BLOCK_INFO |
| 发送私信 | 1 | 固定值 |

### 5.2 枚举类型

#### role_class - 阶层
- `steward` - 管家
- `master` - 主子
- `servant` - 丫鬟/小厮
- `elder` - 元老
- `guest` - 清客

#### steward_route - 管家路线
- `virtuous` - 贤良路线
- `schemer` - 权谋路线
- `undecided` - 未决定

#### intel_type - 情报类型
- `account_leak` - 账目泄露
- `private_action` - 私密行动
- `gift_record` - 馈赠记录
- `visitor_info` - 访客信息
- `elder_favor` - 长辈青睐
- `dui_shi` - 对食情报

#### scene_location - 场景地点
- `yi_hong_yuan` - 怡红院后窗
- `treasury_back` - 管家后账房
- `bridge` - 蜂腰桥
- `gate` - 荣国府大门
- `elder_room` - 贾母处
- `remote_rockery` - 偏僻假山（新增）
- `empty_room` - 空屋（新增）

#### message_type - 消息类型
- `private` - 私信
- `rumor` - 流言
- `batch_order` - 批条/差事
- `system` - 系统消息
- `petition` -  petition
- `accusation` - 举报

---

## 6. RPC 函数参考

### 6.1 辅助函数

#### get_my_player_id()
获取当前登录玩家的 ID。

**返回值**：`uuid`

**兼容性**：
- 云端：通过 `auth.uid()` 识别
- 本地：返回第一个管家玩家

#### get_session_remaining_time(session_id)
获取挂机会话剩余时间（秒）。

**参数**：
- `session_id` - 会话 ID

**返回值**：`integer`

#### get_player_active_session_count(player_uid)
获取玩家活跃会话数。

**参数**：
- `player_uid` - 玩家 ID

**返回值**：`integer`

#### get_scene_listener_count(game_id, scene_key)
获取场景监听人数。

**参数**：
- `game_id` - 游戏局 ID
- `scene_key` - 场景键值

**返回值**：`integer`

#### is_player_intercepted(player_uid)
检查玩家是否被拦截。

**参数**：
- `player_uid` - 玩家 ID

**返回值**：`boolean`

### 6.2 管家行动函数

#### require_steward_and_consume_stamina(cost)
管家身份校验 + 精力扣减。

**参数**：
- `cost` - 精力消耗值

**返回值**：
- `steward_id` - 管家 ID
- `game_id` - 游戏局 ID
- `remaining_stamina` - 剩余精力

#### steward_procure_goods(item_key, quantity)
采办物资。

**参数**：
- `item_key` - 物品模板键
- `quantity` - 数量（默认 1）

**返回值**：`json`
```json
{
  "success": true,
  "ticket_id": "uuid",
  "stamina": 5
}
```

#### steward_assign_task(target_uid, silver_reward)
差使分派。

**参数**：
- `target_uid` - 目标玩家 ID
- `silver_reward` - 赏银（默认 10）

**返回值**：`json`

#### steward_advance_credit(target_uid, amount, deficit_step)
预支批条。

**参数**：
- `target_uid` - 目标玩家 ID
- `amount` - 金额（默认 20）
- `deficit_step` - 亏空增量（默认 5）

**返回值**：`json`

#### steward_search_players(min_count, max_count, love_rate, account_rate)
搜检大观园。

**参数**：
- `min_count` - 最少人数（默认 5）
- `max_count` - 最多人数（默认 10）
- `love_rate` - 情书概率（默认 0.3）
- `account_rate` - 账目碎片概率（默认 0.25）

**返回值**：`json`

#### steward_suppress_rumor(rumor_id)
平息流言。

**参数**：
- `rumor_id` - 流言 ID

**返回值**：`json`

#### steward_block_intel(intel_id)
封锁消息。

**参数**：
- `intel_id` - 情报 ID

**返回值**：`json`
```json
{
  "success": true,
  "blocked_until": "2026-03-19T00:00:00Z",
  "stamina": 3
}
```

---

## 7. 调试指南

### 7.1 本地数据库调试

```powershell
# 查看表结构
docker exec -i honglou_local_db psql -U postgres -d honglou -c "\d players"

# 查看函数列表
docker exec -i honglou_local_db psql -U postgres -d honglou -c "\df public.*"

# 查看玩家数据
docker exec -i honglou_local_db psql -U postgres -d honglou -c "SELECT id, character_name, role_class, stamina FROM players;"

# 强制刷新精力
docker exec -i honglou_local_db psql -U postgres -d honglou -c "UPDATE players SET stamina = stamina_max WHERE role_class = 'steward';"

# 清理挂机会话
docker exec -i honglou_local_db psql -U postgres -d honglou -c "DELETE FROM eavesdrop_sessions;"

# 查看 RLS 策略
docker exec -i honglou_local_db psql -U postgres -d honglou -c "SELECT tablename, policyname, cmd FROM pg_policies;"
```

### 7.2 pgREST API 测试

```powershell
# 查询玩家列表
curl "http://localhost:3000/players?select=*&limit=5" `
  -H "apikey: local-dev-key" `
  -H "Prefer: return=representation"

# 插入测试数据
curl -X POST "http://localhost:3000/players" `
  -H "apikey: local-dev-key" `
  -H "Content-Type: application/json" `
  -H "Prefer: return=representation" `
  -d '{"auth_uid":"test-uid","username":"test","display_name":"测试","role_class":"steward"}'

# 调用 RPC 函数
curl -X POST "http://localhost:3000/rpc/steward_procure_goods" `
  -H "apikey: local-dev-key" `
  -H "Content-Type: application/json" `
  -d '{"p_item_template_key":"generic_supply","p_quantity":5}'
```

### 7.3 Supabase 云端调试

在 Supabase Dashboard → SQL Editor 中执行：

```sql
-- 查看玩家精力
SELECT character_name, stamina, stamina_max, stamina_refreshed_at 
FROM players 
WHERE role_class = 'steward';

-- 查看活跃挂机会话
SELECT s.player_uid, p.character_name, s.scene_key, s.ends_at
FROM eavesdrop_sessions s
JOIN players p ON s.player_uid = p.id
WHERE s.status = 'active';

-- 查看流言状态
SELECT content, stage, spread_count, belief_rate, expires_at
FROM rumors
WHERE status = 'active'
ORDER BY created_at DESC;

-- 手动恢复精力
UPDATE players 
SET stamina = stamina_max, 
    stamina_refreshed_at = now()
WHERE role_class = 'steward';
```

---

## 8. 常见问题

### Q1: 本地数据库无法启动

**症状**：Docker 容器启动失败，报错 "mount failed"

**解决方案**：
```powershell
# 1. 删除旧容器和数据
docker compose -f docker-compose.local-dev.yml down -v

# 2. 检查 SQL 文件路径是否正确
# 确保 docker-compose.local-dev.yml 中的 volumes 路径正确

# 3. 重新启动
docker compose -f docker-compose.local-dev.yml --project-name honglou up -d
```

### Q2: 精力不足无法执行行动

**症状**：调用 RPC 函数返回 "精力不足"

**解决方案**：
```sql
-- 临时增加精力
UPDATE players SET stamina = 10 WHERE auth_uid = 'your-uid';

-- 或刷新精力恢复时间
UPDATE players SET stamina_refreshed_at = now() - INTERVAL '4 hours';
```

### Q3: 测试账号无法登录

**症状**：登录时提示 "玩家不存在"

**解决方案**：
1. 确保已执行 `seed.sql`
2. 检查 `players` 表是否有测试数据：
   ```sql
   SELECT * FROM players WHERE username IN ('fengjie', 'baoyu', 'xiren');
   ```
3. 本地模式下，确保使用正确的 UID 映射（见 `Login.gd`）

### Q4: RPC 函数调用失败

**症状**：调用 `steward_procure_goods` 等函数返回错误

**解决方案**：
1. 检查当前玩家是否为管家：
   ```sql
   SELECT role_class FROM players WHERE id = 'your-player-id';
   ```
2. 检查精力是否足够：
   ```sql
   SELECT stamina, stamina_max FROM players WHERE id = 'your-player-id';
   ```
3. 本地环境下，确保 `anon` 角色有执行权限：
   ```sql
   GRANT EXECUTE ON FUNCTION public.steward_procure_goods TO anon;
   ```

### Q5: 数据不同步

**症状**：本地数据库与云端数据结构不一致

**解决方案**：
1. 统一使用 `full_schema.sql` 作为标准架构
2. 本地重新初始化：
   ```powershell
   docker compose down -v
   docker compose up -d
   ```
3. 云端执行架构更新（如有必要）

---

## 附录 A: 测试账号

执行 `seed.sql` 后创建的测试账号：

| 邮箱 | 密码 | 角色 | 扮演人物 | 银两 | 私产 |
|------|------|------|----------|------|------|
| fengjie@example.com | 123456 | 管家 | 凤姐 | 100 | 500 |
| baoyu@test.com | 123456 | 主子 | 贾宝玉 | 50 | 0 |
| daiyu@test.com | 123456 | 主子 | 林黛玉 | 30 | 0 |
| xiren@example.com | 123456 | 丫鬟 | 袭人 | 10 | 0 |
| qingwen@example.com | 123456 | 丫鬟 | 晴雯 | 5 | 0 |

---

## 附录 B: 版本历史

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| 1.0 | 2026-03-15 | 初始架构 |
| 1.1 | 2026-03-17 | 修复 ledger_entries、添加精力系统 |
| 2.0 | 2026-03-18 | 合并所有 SQL 文件，统一文档 |

---

**文档结束**
