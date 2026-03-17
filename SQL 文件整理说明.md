# SQL 文件整理说明

## 问题背景
2026-03-17 修复了 `ledger_entries` 表结构与 Edge Function 代码不匹配的问题，并恢复了精力系统。

---

## SQL 文件结构

本项目有 **3 份 SQL schema 文件**，需要保持同步：

| 文件 | 用途 | 同步方式 |
|------|------|----------|
| `schema.sql` | 主 schema 文件（手动维护） | 直接编辑 |
| `combined_schema.sql` | 本地 Docker 初始化用 | 从 schema.sql 复制 |
| `supabase/migrations/*.sql` | Supabase 增量迁移文件 | 增量迁移 |

---

## 文件说明

### 1. schema.sql
- **位置**: 项目根目录
- **用途**: 主 schema 文件，包含完整的数据库结构定义
- **更新方式**: 直接编辑
- **版本**: 2026-03-17（已更新 ledger_entries、steward_accounts、精力系统）

### 2. combined_schema.sql
- **位置**: 项目根目录
- **用途**: Docker 容器启动时自动执行（`docker-entrypoint-initdb.d/`）
- **更新方式**: 从 `schema.sql` 复制
- **注意**: 本地数据库首次创建时使用

### 3. supabase/migrations/
- **位置**: `supabase/migrations/` 目录
- **用途**: Supabase 增量迁移文件
- **文件列表**:
  - `20260315000000_init_schema.sql` - 初始 schema（已更新 ledger_entries）
  - `20260317000001_fix_ledger_entries_schema.sql` - ledger_entries 修复迁移
  - `20260317000002_add_treasury_rpc_functions.sql` - 银库 RPC 函数
  - `20260317000003_add_steward_accounts_ledger_columns.sql` - steward_accounts 账本列
  - `20260317000004_add_allowance_records_table.sql` - allowance_records 表
  - `20260317000005_add_stamina_system.sql` - 精力系统

---

## 主要修复内容

### 1. ledger_entries 表修复

**修改前（旧结构）**:
```sql
CREATE TABLE ledger_entries (
    id uuid PRIMARY KEY,
    game_id uuid NOT NULL,
    actor_id uuid NOT NULL,
    target_id uuid,
    action_type action_type NOT NULL,      -- ❌ 删除
    amount int,
    approval_status approval_status,       -- ❌ 删除
    created_at,
    updated_at
);
```

**修改后（新结构）**:
```sql
CREATE TABLE ledger_entries (
    id uuid PRIMARY KEY,
    game_id uuid NOT NULL,
    treasury_id uuid,                      -- ✅ 新增：关联银库
    actor_id uuid NOT NULL,
    target_id uuid,
    ledger_type text,                      -- ✅ 新增：public/private
    entry_type text,                       -- ✅ 新增：allocation/procurement/advance
    amount int,
    note text,                             -- ✅ 新增：备注
    created_at,
    updated_at
);
```

### 2. steward_accounts 表修复

添加了 `public_ledger` 和 `private_ledger` 字段（jsonb 类型）。

### 3. allowance_records 表恢复

恢复了月例发放记录表，该表在之前的修改中丢失。

### 4. 精力系统恢复

- 添加 `players.stamina_refreshed_at` 字段
- 创建 `procurement_tickets` 表
- 扩展 `intel_fragments` 表（情报封锁字段）
- 创建精力相关 RPC 函数：
  - `require_steward_and_consume_stamina` - 管家身份校验 + 精力扣减
  - `steward_procure_goods` - 采办物资
  - `steward_assign_task` - 差使分派
  - `steward_advance_credit` - 预支批条
  - `steward_search_players` - 搜检功能
  - `steward_suppress_rumor` - 平息流言
  - `steward_block_intel` - 封锁消息

### 5. 银库 RPC 函数

- `modify_player_stats` - 修改玩家属性
- `decrement_treasury` - 扣除银库
- `distribute_allowance_rpc` - 单人发放月例
- `bulk_distribute_allowance_rpc` - 批量发放月例
- `get_treasury_stats` - 获取银库统计

---

## 同步流程

### 本地开发
```powershell
# 1. 启动本地数据库
docker-compose -p honglou -f docker-compose.local-dev.yml up -d

# 2. 数据库已自动使用 combined_schema.sql 初始化
# 如需重新初始化，删除并重建容器：
docker-compose -p honglou -f docker-compose.local-dev.yml down -v
docker-compose -p honglou -f docker-compose.local-dev.yml up -d
```

### 推送 Supabase 云端
```powershell
# 1. 设置 Access Token
$env:SUPABASE_ACCESS_TOKEN = "<你的 Token>"

# 2. 推送迁移
supabase db push
```

---

## 验证方法

### 本地数据库
```powershell
# 查看表结构
docker exec -i honglou_local_db psql -U postgres -d honglou -c "\d ledger_entries"
docker exec -i honglou_local_db psql -U postgres -d honglou -c "\d steward_accounts"
docker exec -i honglou_local_db psql -U postgres -d honglou -c "\d allowance_records"

# 查看函数
docker exec -i honglou_local_db psql -U postgres -d honglou -c "\df public.distribute_allowance_rpc"
docker exec -i honglou_local_db psql -U postgres -d honglou -c "\df public.require_steward_and_consume_stamina"

# 测试查询
docker exec -i honglou_local_db psql -U postgres -d honglou -c "SELECT * FROM ledger_entries LIMIT 1;"
```

### Supabase 云端
在 Supabase Dashboard → SQL Editor 中执行：
```sql
\d ledger_entries
```

---

## 文件更新记录

| 日期 | 文件 | 操作 |
|------|------|------|
| 2026-03-17 | `schema.sql` | 更新 ledger_entries、steward_accounts、精力系统 |
| 2026-03-17 | `combined_schema.sql` | 同步 schema.sql |
| 2026-03-17 | `supabase/migrations/20260315000000_init_schema.sql` | 更新 ledger_entries |
| 2026-03-17 | `supabase/migrations/20260317000001_fix_ledger_entries_schema.sql` | 修复迁移 |
| 2026-03-17 | `supabase/migrations/20260317000002_add_treasury_rpc_functions.sql` | 银库 RPC |
| 2026-03-17 | `supabase/migrations/20260317000003_add_steward_accounts_ledger_columns.sql` | 账本列 |
| 2026-03-17 | `supabase/migrations/20260317000004_add_allowance_records_table.sql` | 月例表 |
| 2026-03-17 | `supabase/migrations/20260317000005_add_stamina_system.sql` | 精力系统 |

---

## 注意事项

1. **本地 vs 云端**: 
   - 本地数据库使用 `combined_schema.sql` 一次性初始化
   - Supabase 云端使用增量迁移文件（migrations/）

2. **保持同步**: 修改 schema 后，需要同时更新：
   - `schema.sql`
   - `combined_schema.sql`
   - 如需云端同步，创建新的 migration 文件

3. **迁移顺序**: Supabase 按文件名时间戳顺序执行迁移
   - `20260315000000_*.sql` 先执行
   - `20260317000001_*.sql` 后执行

4. **精力恢复机制**: 每 2 小时自动恢复 1 点精力

---

**更新时间**: 2026-03-17
1. ledger_entries 表修复
2. steward_accounts 表修复
3. allowance_records 表恢复
4. 精力系统恢复
