# 《红楼回忆志》数据库迁移回滚预案

**文档版本**: 1.0  
**最后更新**: 2026-03-20  
**负责人**: SRE 团队  
**RTO**: < 15 分钟  
**RPO**: 0 秒

---

## 1. 回滚触发条件

| 级别 | 触发条件 | 响应时间 | 动作 |
|------|----------|----------|------|
| **Level 1: 警告** | 错误率 > 0.05%<br>P99 延迟 +30ms | 10 分钟 | 继续观察<br>通知 on-call |
| **Level 2: 严重** | 错误率 > 0.1%<br>P99 延迟 +50ms<br>校验失败 > 10 条 | 5 分钟 | 准备回滚<br>通知负责人 |
| **Level 3: 紧急** | 错误率 > 1%<br>P99 延迟 +200ms<br>业务告警触发 | 立即 | 执行紧急回滚 |

---

## 2. 各阶段回滚操作

### Phase 1 准备阶段

| 回滚触发条件 | 回滚操作 | 预计恢复时间 |
|------------|---------|------------|
| 新表创建失败 | 删除已创建的新表<br>清理迁移配置 | < 5 分钟 |
| 触发器创建失败 | DROP TRIGGER<br>删除函数 | < 5 分钟 |
| 索引创建超时 (>30min) | DROP INDEX<br>重新评估 | < 5 分钟 |

### Phase 2 全量迁移阶段

| 回滚触发条件 | 回滚操作 | 预计恢复时间 |
|------------|---------|------------|
| 迁移错误率 > 0.1% | 暂停迁移任务<br>DELETE FROM 新表<br>TRUNCATE 进度表 | < 10 分钟 |
| 源表锁等待 > 10s | 暂停迁移<br>REINDEX 源表 | < 10 分钟 |
| 主库 CPU > 90% | 暂停迁移<br>调整 batch_size | < 5 分钟 |

### Phase 3 双写阶段

| 回滚触发条件 | 回滚操作 | 预计恢复时间 |
|------------|---------|------------|
| 双写失败率 > 0.05% | 关闭双写开关<br>恢复单写旧表 | < 5 分钟 |
| 写入延迟 P99 +50ms | 关闭双写<br>清理新表脏数据 | < 5 分钟 |
| 数据校验失败 > 10 条 | 关闭双写<br>修复不一致记录 | < 10 分钟 |

### Phase 4 切换阶段

| 回滚触发条件 | 回滚操作 | 预计恢复时间 |
|------------|---------|------------|
| 读新表错误率 > 0.1% | 切换读回旧表<br>关闭新表路由 | < 3 分钟 |
| 查询延迟 P99 +100ms | 切回旧表<br>启用旧表视图 | < 3 分钟 |
| 业务告警触发 | 紧急回滚<br>验证业务恢复 | < 5 分钟 |

---

## 3. 应用层回滚脚本

```bash
#!/bin/bash
# rollback_application.sh - 应用层回滚脚本

set -e

echo "=== 开始应用层回滚 ==="

# 1. 关闭双写开关
echo "[1/3] 关闭双写开关..."
curl -X POST http://apollo-config/changesets/apply \
  -H "Authorization: Bearer $APOLLO_TOKEN" \
  -d '{"appId":"honglou-game","namespace":"migration","key":"dual_write.enabled","value":"false"}'

# 2. 切换读表路由
echo "[2/3] 切换读表路由到旧表..."
curl -X POST http://apollo-config/changesets/apply \
  -H "Authorization: Bearer $APOLLO_TOKEN" \
  -d '{"appId":"honglou-game","namespace":"migration","key":"read_target","value":"old_table"}'

# 3. 禁用新表访问
echo "[3/3] 禁用新表访问..."
curl -X POST http://apollo-config/changesets/apply \
  -H "Authorization: Bearer $APOLLO_TOKEN" \
  -d '{"appId":"honglou-game","namespace":"migration","key":"new_table.enabled","value":"false"}'

echo "=== 应用层回滚完成 ==="

# 验证
curl -s http://app-health/migration/status | jq '.dual_write_enabled'  # 应为 false
curl -s http://app-health/migration/status | jq '.read_target'  # 应为 "old_table"
```

---

## 4. 数据层回滚 SQL

```sql
-- ============================================================
-- 数据层回滚：将新表数据同步回旧表
-- 执行时间：< 10 分钟
-- ============================================================

-- 4.1 暂停触发器
ALTER TABLE public.players DISABLE TRIGGER trg_sync_player_to_stats;
ALTER TABLE public.messages DISABLE TRIGGER trg_sync_message_to_rumor;

-- 4.2 回滚 player_role_stats → players
UPDATE public.players p
SET 
    role_class = s.role_class,
    silver = s.silver,
    reputation = s.reputation,
    face_value = s.face_value,
    stamina = s.stamina,
    qi_points = s.qi_points,
    updated_at = now()
FROM public.player_role_stats s
WHERE p.id = s.player_id;

-- 4.3 回滚 rumors → messages
UPDATE public.messages m
SET 
    stage = r.stage,
    expires_at = r.expires_at,
    is_tampered = r.is_tampered,
    original_content = r.original_content,
    updated_at = now()
FROM public.rumors r
WHERE m.id = r.message_id;

-- 4.4 清理新表
DELETE FROM public.player_role_stats;
DELETE FROM public.rumors;

-- 4.5 清理迁移辅助表
TRUNCATE public.migration_progress;
TRUNCATE public.migration_errors;
TRUNCATE public.migration_validation;

-- 4.6 恢复触发器
ALTER TABLE public.players ENABLE TRIGGER trg_sync_player_to_stats;
ALTER TABLE public.messages ENABLE TRIGGER trg_sync_message_to_rumor;
```

---

## 5. 监控指标清单

### Grafana 面板关键指标

| 指标名称 | 告警阈值 | 检查频率 |
|----------|----------|----------|
| 迁移错误率 | > 0.1% | 1 分钟 |
| 查询延迟 P99 | > 100ms | 1 分钟 |
| 数据校验失败数 | > 10 | 5 分钟 |
| 双写延迟 | > 50ms | 1 分钟 |
| 主库 CPU 使用率 | > 90% | 1 分钟 |
| 活跃连接数 | > 100 | 1 分钟 |
| 锁等待时间 P99 | > 10 秒 | 1 分钟 |

### Prometheus 告警规则

```yaml
groups:
  - name: migration_alerts
    rules:
      - alert: MigrationErrorRateCritical
        expr: rate(migration_errors_total[5m]) / rate(migration_rows_processed_total[5m]) > 0.001
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "迁移错误率超过 0.1%"
      
      - alert: MigrationLatencyIncrease
        expr: histogram_quantile(0.99, rate(db_query_duration_seconds_bucket[5m])) * 1000 > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "查询延迟 P99 超过 100ms"
```

---

## 6. 回滚演练计划

### 演练场景 A: 双写阶段回滚

```markdown
## 前置条件
- [ ] 迁移进行到 Phase 3 (双写)
- [ ] 双写已开启 1 小时

## 演练步骤

### T+0min: 注入故障
psql -c "UPDATE player_role_stats SET silver = silver + 1000 WHERE player_id = 'xxx';"

### T+1min: 触发告警
- 预期：数据校验失败告警

### T+3min: 决策回滚
- On-call 确认告警
- 通知迁移负责人

### T+5min: 执行回滚
./rollback_application.sh
psql -f rollback_data.sql

### T+10min: 验证恢复
curl http://staging-api/health  # 应返回 healthy

### T+30min: 演练总结
- 记录实际 RTO/RPO
- 更新文档
```

---

## 7. 应急联系人

| 角色 | 姓名 | 电话 | Slack |
|------|------|------|-------|
| 迁移总负责人 | ______ | ______ | @______ |
| SRE On-call | ______ | ______ | @______ |
| DBA On-call | ______ | ______ | @______ |
| 开发负责人 | ______ | ______ | @______ |

---

## 8. 回滚检查清单

```markdown
# 回滚执行检查清单

## 决策阶段
- [ ] 确认告警级别
- [ ] 通知相关负责人
- [ ] 决策执行回滚

## 执行阶段
- [ ] 关闭双写开关
- [ ] 切换读表路由
- [ ] 执行数据回滚 SQL
- [ ] 清理迁移辅助表

## 验证阶段
- [ ] 验证业务功能恢复
- [ ] 验证监控指标正常
- [ ] 验证数据一致性

## 总结阶段
- [ ] 记录实际 RTO
- [ ] 记录实际问题
- [ ] 更新改进项

签字确认：
- 执行人：____________ 日期：____________
- 审核人：____________ 日期：____________
```

---

**文档审批记录**

| 版本 | 审批人 | 日期 | 意见 |
|------|--------|------|------|
| 1.0 | ______ | ______ | ______ |
