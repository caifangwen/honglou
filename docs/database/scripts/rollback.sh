#!/bin/bash
# ============================================================
# 《红楼回忆志》数据库迁移回滚脚本
# 用法：./rollback.sh [--step all|app|data] [--force]
# ============================================================

set -e

# 配置
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-honglou_db}"
DB_USER="${DB_USER:-postgres}"
STEP="${1:-all}"
FORCE="${2:-}"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}============================================================${NC}"
echo "《红楼回忆志》数据库迁移回滚"
echo "============================================================"
echo "数据库：${DB_NAME}@${DB_HOST}:${DB_PORT}"
echo "回滚步骤：${STEP}"
echo "============================================================${NC}"

# 应用层回滚
rollback_app() {
    echo -e "\n${YELLOW}=== 应用层回滚 ===${NC}"
    
    # 关闭双写开关
    echo "[1/3] 关闭双写开关..."
    if command -v curl &> /dev/null; then
        curl -s -X POST "http://localhost:8080/admin/migration/dual_write" \
            -H "Content-Type: application/json" \
            -d '{"enabled": false}' || echo "跳过（配置服务不可用）"
    else
        echo "跳过（curl 不可用）"
    fi
    
    # 切换读表路由
    echo "[2/3] 切换读表路由到旧表..."
    curl -s -X POST "http://localhost:8080/admin/migration/read_target" \
        -H "Content-Type: application/json" \
        -d '{"target": "old_table"}' || echo "跳过"
    
    # 禁用新表访问
    echo "[3/3] 禁用新表访问..."
    curl -s -X POST "http://localhost:8080/admin/migration/new_table" \
        -H "Content-Type: application/json" \
        -d '{"enabled": false}' || echo "跳过"
    
    echo -e "${GREEN}✅ 应用层回滚完成${NC}"
}

# 数据层回滚
rollback_data() {
    echo -e "\n${YELLOW}=== 数据层回滚 ===${NC}"
    
    # 暂停触发器
    echo "[1/5] 暂停触发器..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        ALTER TABLE public.players DISABLE TRIGGER trg_sync_player_to_stats;
        ALTER TABLE public.messages DISABLE TRIGGER trg_sync_message_to_rumor;
    "
    
    # 回滚 player_role_stats → players
    echo "[2/5] 回滚玩家属性到旧表..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
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
    "
    
    # 回滚 rumors → messages
    echo "[3/5] 回滚流言到旧表..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        UPDATE public.messages m
        SET 
            stage = r.stage,
            expires_at = r.expires_at,
            is_tampered = r.is_tampered,
            original_content = r.original_content,
            updated_at = now()
        FROM public.rumors r
        WHERE m.id = r.message_id;
    "
    
    # 清理新表
    echo "[4/5] 清理新表数据..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        DELETE FROM public.player_role_stats;
        DELETE FROM public.rumors;
        DELETE FROM public.ledger_entries;
    "
    
    # 清理迁移辅助表
    echo "[5/5] 清理迁移辅助表..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        TRUNCATE public.migration_progress;
        TRUNCATE public.migration_errors;
        TRUNCATE public.migration_validation;
    "
    
    # 恢复触发器
    echo "恢复触发器..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        ALTER TABLE public.players ENABLE TRIGGER trg_sync_player_to_stats;
        ALTER TABLE public.messages ENABLE TRIGGER trg_sync_message_to_rumor;
    "
    
    echo -e "${GREEN}✅ 数据层回滚完成${NC}"
}

# 验证回滚
verify_rollback() {
    echo -e "\n${YELLOW}=== 验证回滚结果 ===${NC}"
    
    # 检查旧表数据
    echo "[1/3] 检查旧表数据..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 'players' AS table_name, COUNT(*) AS row_count FROM public.players
        UNION ALL
        SELECT 'messages', COUNT(*) FROM public.messages WHERE message_type='rumor';
    "
    
    # 检查新表为空
    echo "[2/3] 检查新表已清空..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 'player_role_stats' AS table_name, COUNT(*) AS row_count FROM public.player_role_stats
        UNION ALL
        SELECT 'rumors', COUNT(*) FROM public.rumors;
    "
    
    # 检查迁移进度
    echo "[3/3] 检查迁移进度已重置..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT task_name, status, migrated_rows FROM public.migration_progress;
    "
    
    echo -e "${GREEN}✅ 验证完成${NC}"
}

# 主流程
main() {
    start_time=$(date +%s)
    
    case "$STEP" in
        app)
            rollback_app
            ;;
        data)
            rollback_data
            ;;
        all|*)
            rollback_app
            rollback_data
            verify_rollback
            ;;
    esac
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    echo -e "\n${YELLOW}============================================================${NC}"
    echo "回滚完成，耗时：${duration}秒"
    echo -e "${YELLOW}============================================================${NC}"
}

main
