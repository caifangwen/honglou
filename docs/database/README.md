# 《红楼回忆志》数据库迁移项目文档索引

**项目**: 数据库 Schema 重构 + 数据规范化迁移  
**创建日期**: 2026-03-20  
**数据库类型**: PostgreSQL 15 (Supabase)

---

## 📁 文档目录结构

```
docs/database/
├── 01-schema-scan-report.md          # 数据库结构扫描报告
├── 02-capacity-analysis-report.md    # 容量分析报告
├── 03-dependency-graph-report.md     # 依赖图谱分析
├── 04-normalization-audit-report.md  # 规范化审计报告
├── 05-sql-performance-tuning-report.md # SQL 性能调优报告
├── 06-new-schema-ddl.sql             # 新 Schema DDL
├── 07-migration-script.sql           # 迁移脚本
├── 08-rollback-runbook.md            # 回滚预案
└── scripts/
    ├── validate_migration.py         # 数据验证脚本
    └── rollback.sh                   # 回滚执行脚本
```

---

## 📋 各阶段文档说明

### 阶段一：现状分析

| 文档 | 内容 | 用途 |
|------|------|------|
| [01-schema-scan-report.md](01-schema-scan-report.md) | 18 张表结构、字段详情、ER 图 | 了解当前数据库结构 |
| [02-capacity-analysis-report.md](02-capacity-analysis-report.md) | 数据增长预测、分区建议 | 容量规划参考 |
| [03-dependency-graph-report.md](03-dependency-graph-report.md) | 表 - 服务矩阵、重构影响评分 | 评估重构风险 |

### 阶段二：设计规范

| 文档 | 内容 | 用途 |
|------|------|------|
| [04-normalization-audit-report.md](04-normalization-audit-report.md) | 1NF/2NF/3NF 违反项、改造方案 | 规范化改造依据 |
| [05-sql-performance-tuning-report.md](05-sql-performance-tuning-report.md) | 慢查询分析、索引推荐 | 性能优化参考 |
| [06-new-schema-ddl.sql](06-new-schema-ddl.sql) | 完整的新表结构 DDL | 执行建表 |

### 阶段三：迁移执行

| 文档 | 内容 | 用途 |
|------|------|------|
| [07-migration-script.sql](07-migration-script.sql) | 断点续传迁移函数 | 执行数据迁移 |
| [scripts/validate_migration.py](scripts/validate_migration.py) | 数据一致性验证 | 迁移后校验 |
| [scripts/rollback.sh](scripts/rollback.sh) | 回滚执行脚本 | 紧急回滚 |
| [08-rollback-runbook.md](08-rollback-runbook.md) | 回滚预案 Runbook | SRE 值班参考 |

---

## 🚀 快速开始

### 1. 查看当前数据库状态

```bash
# 连接数据库
psql -h localhost -U postgres -d honglou_db

# 查看表结构
\dt public.*

# 查看当前表行数
SELECT 
    tablename,
    (xpath('/row/cnt/text()', xml_count))[1]::text::int AS row_count
FROM (
    SELECT tablename, query_to_xml(format('SELECT COUNT(*) as cnt FROM %I', tablename), false, true, '') AS xml_count
    FROM pg_tables
    WHERE schemaname = 'public'
) t;
```

### 2. 执行规范化改造

```sql
-- 执行新 Schema DDL
\i docs/database/06-new-schema-ddl.sql

-- 验证新表创建成功
\dt public.*
```

### 3. 执行数据迁移

```sql
-- 执行迁移脚本
\i docs/database/07-migration-script.sql

-- 查看迁移进度
SELECT * FROM public.migration_status;

-- 执行迁移
SELECT * FROM public.migrate_players_to_stats(1000, 100, true, 0);
SELECT * FROM public.migrate_messages_to_rumors(500, 200, 0);
```

### 4. 验证数据一致性

```bash
# 执行 Python 验证脚本
python docs/database/scripts/validate_migration.py

# 查看验证报告
cat validation_report.md
```

### 5. 紧急回滚（如需要）

```bash
# 执行回滚脚本
bash docs/database/scripts/rollback.sh all

# 或手动执行回滚 SQL
psql -f docs/database/08-rollback-runbook.md
```

---

## 📊 关键指标

| 指标 | 当前值 | 目标值 | 状态 |
|------|:------:|:------:|:----:|
| 表数量 | 18 | 22 | 🟢 |
| 规范化合规率 | 75% | 95% | 🟡 |
| 预估性能提升 | - | 90% | 🟢 |
| 迁移 RTO | - | < 15 分钟 | 🟢 |
| 迁移 RPO | - | 0 秒 | 🟢 |

---

## ⚠️ 注意事项

1. **执行前备份**: 所有操作前请先备份数据库
2. **测试环境验证**: 先在测试环境完整演练
3. **低峰期执行**: 迁移操作建议在凌晨执行
4. **监控告警**: 执行期间确保监控告警正常
5. **回滚准备**: 确保回滚脚本可随时执行

---

## 📞 联系方式

| 角色 | 负责人 | 联系方式 |
|------|--------|----------|
| 项目负责人 | ______ | ______ |
| DBA | ______ | ______ |
| SRE | ______ | ______ |

---

**文档生成日期**: 2026-03-20  
**文档版本**: 1.0
