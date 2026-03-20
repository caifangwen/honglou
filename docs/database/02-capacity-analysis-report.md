# 《红楼回忆志》数据库容量分析报告

**分析日期**: 2026-03-20  
**数据库类型**: PostgreSQL 15 (Supabase)  
**当前阶段**: 开发初期（种子数据约 20 条玩家记录）

---

## 1. 大表识别（预估 TOP 10）

基于游戏业务场景和数据生成频率的预估分析：

| 排名 | 表名 | 预估行数 (当前) | 预估行数 (6 月) | 预估行数 (12 月) | 单行大小 | 预估存储 (12 月) | 增长驱动 |
|:---:|------|:--------------:|:--------------:|:---------------:|:--------:|:---------------:|----------|
| 1 | `messages` | ~0 | 50,000 | 200,000 | ~500B | ~95MB | 私信/流言/系统消息 |
| 2 | `intel_fragments` | ~0 | 30,000 | 120,000 | ~400B | ~46MB | 挂机监听产出 |
| 3 | `ledger_entries` | ~0 | 20,000 | 80,000 | ~300B | ~23MB | 账本记录累积 |
| 4 | `action_approvals` | ~0 | 15,000 | 60,000 | ~350B | ~20MB | 管家行动日志 |
| 5 | `eavesdrop_sessions` | ~0 | 10,000 | 40,000 | ~250B | ~9.5MB | 挂机会话历史 |
| 6 | `rumors` | ~0 | 5,000 | 20,000 | ~350B | ~6.7MB | 流言传播记录 |
| 7 | `players` | 20 | 500 | 2,000 | ~400B | ~0.8MB | 用户注册增长 |
| 8 | `intel_trades` | ~0 | 3,000 | 12,000 | ~200B | ~2.3MB | 情报交易 |
| 9 | `procurement_tickets` | ~0 | 5,000 | 20,000 | ~200B | ~3.8MB | 采办票据 |
| 10 | `games` | 1 | 50 | 200 | ~300B | ~0.06MB | 游戏局更替 |

**注**: 预估基于假设场景——日活用户 (DAU) 100-500 人，单局游戏时长 7-30 天

---

## 2. 增长预测

### 2.1 核心假设

| 参数 | 保守估计 | 乐观估计 |
|------|:--------:|:--------:|
| 日活跃用户 (DAU) | 50 | 200 |
| 单用户日均消息数 | 10 | 30 |
| 单用户日均情报产出 | 5 | 15 |
| 单用户日均行动数 | 3 | 10 |
| 平均在线游戏局数 | 5 | 20 |

### 2.2 增长趋势示意（总行数）

```
总行数增长预测 (单位：千行)
                                   
  500 ┤                              ╭────── 乐观估计
      │                         ╭──╯
  400 ┤                    ╭──╮╭╯
      │               ╭──╮╭╯  ╰╮
  300 ┤          ╭──╮╭╯  ╰╮  ╭╯
      │     ╭──╮╭╯  ╰╮  ╭╯╭─╯
  200 ┤╭──╮╭╯  ╰╮  ╭╯  ╭╯╭╯         ═════ 保守估计
      │  ╰╯  ╭╯  ╰╮  ╭╯╭╯
  100 ┤      ╰╯  ╭╯  ╰╯╭╯
      │          ╰─────╯
    0 ┼────┬────┬────┬────┬────┬────┬────┬────
      0M   3M   6M   9M   12M  15M  18M  24M
                  时间 (月)
```

### 2.3 存储容量预测

| 时间 | 总行数 | 总存储 (含索引) | 月增长 |
|------|:------:|:---------------:|:------:|
| 当前 | ~50 | < 1 MB | - |
| 6 月 | ~140,000 | ~200 MB | ~33 MB/月 |
| 12 月 | ~550,000 | ~800 MB | ~50 MB/月 |
| 24 月 | ~2,200,000 | ~3.2 GB | ~100 MB/月 |

---

## 3. 热点表分析（基于业务逻辑推断）

由于暂无 Slow Query Log 和 APM 数据，以下基于代码逻辑推断读写频率：

| 表名 | 读频率 | 写频率 | 热点原因 | 潜在瓶颈 |
|------|:------:|:------:|----------|----------|
| `players` | 🔴 高 | 🟡 中 | 每请求必查玩家信息 | 并发更新 stamina/silver |
| `messages` | 🟡 中 | 🔴 高 | 消息实时写入 | 未读消息查询、过期清理 |
| `intel_fragments` | 🟡 中 | 🟡 中 | 情报列表展示 | 过期情报清理 |
| `eavesdrop_sessions` | 🟡 中 | 🔴 高 | 挂机状态频繁更新 | 会话到期检查 |
| `games` | 🔴 高 | 🟢 低 | 游戏状态全局读取 | 亏空/冲突值更新 |
| `treasury` | 🟡 中 | 🟡 中 | 银库状态查询 | 并发扣减银两 |

---

## 4. 分区建议

### 4.1 推荐分区的表

| 表名 | 推荐分区策略 | 分区键 | 理由 |
|------|:------------:|--------|------|
| `messages` | **范围分区 (时间)** | `created_at` (月/周) | 数据量大，按时间归档方便 |
| `intel_fragments` | **范围分区 (时间)** | `obtained_at` (月) | 情报有过期机制，便于清理 |
| `ledger_entries` | **范围分区 (时间)** | `created_at` (月) | 账本按时间查询频繁 |
| `eavesdrop_sessions` | **范围分区 (时间)** | `starts_at` (月) | 历史会话可归档 |
| `games` | **列表分区 (状态)** | `status` | 活跃局/历史局分离 |

### 4.2 分区示例（messages 表）

```sql
-- 按月分区示例
CREATE TABLE messages_y2026m03 PARTITION OF messages
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

CREATE TABLE messages_y2026m04 PARTITION OF messages
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');

-- 创建分区索引
CREATE INDEX idx_messages_y2026m03_receiver 
    ON messages_y2026m03 (game_id, receiver_uid);
```

---

## 5. 归档候选表

### 5.1 可安全归档的数据

| 表名 | 归档条件 | 归档策略 | 保留期 |
|------|----------|----------|--------|
| `messages` | `created_at < NOW() - INTERVAL '90 days'` AND `is_read = true` | 移至 `messages_archive` 表或冷存储 | 90 天 |
| `intel_fragments` | `expires_at < NOW()` OR `is_used = true` AND `obtained_at < NOW() - INTERVAL '30 days'` | 删除或归档 | 30 天 |
| `eavesdrop_sessions` | `status = 'completed'` AND `ends_at < NOW() - INTERVAL '30 days'` | 归档后删除 | 30 天 |
| `rumors` | `status = 'expired'` OR `created_at < NOW() - INTERVAL '7 days'` | 直接删除 | 7 天 |
| `action_approvals` | `created_at < NOW() - INTERVAL '180 days'` | 移至审计归档表 | 180 天 |
| `games` | `status = 'ended'` AND `ended_at < NOW() - INTERVAL '90 days'` | 归档整局数据 | 90 天 |

### 5.2 归档脚本示例

```sql
-- 创建归档表
CREATE TABLE messages_archive (LIKE public.messages INCLUDING ALL);

-- 定期归档任务 (pg_cron 或外部调度)
INSERT INTO messages_archive
SELECT * FROM public.messages
WHERE created_at < NOW() - INTERVAL '90 days'
  AND is_read = true;

DELETE FROM public.messages
WHERE created_at < NOW() - INTERVAL '90 days'
  AND is_read = true;

-- 清理过期情报
DELETE FROM public.intel_fragments
WHERE expires_at < NOW() 
   OR (is_used = true AND obtained_at < NOW() - INTERVAL '30 days');
```

---

## 6. 容量风险评级

### 综合评级：**🟢 低**

| 维度 | 评级 | 说明 |
|------|:----:|------|
| **存储容量** | 🟢 低 | 24 月预估 < 5GB，Supabase 免费额度足够 |
| **行数增长** | 🟡 中 | 消息表可能突破百万行，需关注索引效率 |
| **查询性能** | 🟢 低 | 当前 schema 设计合理，索引覆盖充分 |
| **归档机制** | 🟡 中 | 有过期字段设计，但需实现自动清理任务 |
| **并发风险** | 🟡 中 | `players` 表高频更新需关注行锁竞争 |

### 风险项清单

| 优先级 | 风险描述 | 建议措施 |
|:------:|----------|----------|
| P2 | `messages` 表快速增长导致查询变慢 | 实现按月分区 + 定期归档 |
| P2 | 过期数据无自动清理机制 | 配置 `pg_cron` 定时清理任务 |
| P3 | `players.stamina` 高频更新可能产生锁竞争 | 考虑使用 `UPDATE ... FROM` 批量更新 |
| P3 | 情报表 `is_sold/is_used` 索引缺失 | 已覆盖，无需额外操作 |

---

## 7. 建议行动项

| 优先级 | 行动项 | 预计工作量 |
|:------:|--------|------------|
| 🔴 P0 | 配置 `pg_cron` 定时清理过期情报/消息 | 2 小时 |
| 🟡 P1 | 为 `messages` 表实现按月分区 | 4 小时 |
| 🟡 P1 | 创建归档表 `messages_archive` / `intel_fragments_archive` | 2 小时 |
| 🟢 P2 | 监控 `players` 表并发更新性能 | 持续观察 |
| 🟢 P2 | 设置 Supabase 存储告警阈值 (80% 使用率) | 1 小时 |

---

**备注**: 本分析基于业务场景预估，建议在上线后接入 APM 工具（如 pg_stat_statements）获取真实运行数据后进行二次分析。
