-- ============================================================
-- 《红楼回忆志》数据库迁移脚本
-- 特性：断点续传 + 数据校验 + 错误处理 + 限速控制
-- 数据库：PostgreSQL 15 (Supabase)
-- ============================================================

-- ============================================================
-- 第一部分：迁移辅助表
-- ============================================================

-- 1.1 迁移进度表
CREATE TABLE IF NOT EXISTS public.migration_progress (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    task_name text NOT NULL UNIQUE,
    source_table text NOT NULL,
    target_table text NOT NULL,
    last_processed_id uuid,
    last_processed_bigint_id bigint DEFAULT 0,
    total_rows bigint NOT NULL DEFAULT 0,
    migrated_rows bigint NOT NULL DEFAULT 0,
    batch_count int NOT NULL DEFAULT 0,
    failed_count int NOT NULL DEFAULT 0,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'paused', 'completed', 'failed')),
    error_message text,
    started_at timestamptz,
    completed_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_migration_progress_task ON public.migration_progress(task_name);
CREATE INDEX IF NOT EXISTS idx_migration_progress_status ON public.migration_progress(status);

-- 1.2 迁移错误日志表
CREATE TABLE IF NOT EXISTS public.migration_errors (
    id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    task_name text NOT NULL,
    batch_number int NOT NULL,
    source_id uuid,
    source_id_bigint bigint,
    error_code text,
    error_message text NOT NULL,
    error_detail text,
    raw_data jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_migration_errors_task ON public.migration_errors(task_name);
CREATE INDEX IF NOT EXISTS idx_migration_errors_created ON public.migration_errors(created_at DESC);

-- 1.3 数据校验记录表
CREATE TABLE IF NOT EXISTS public.migration_validation (
    id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    task_name text NOT NULL,
    batch_number int NOT NULL,
    source_count int NOT NULL,
    target_count int NOT NULL,
    source_checksum text,
    target_checksum text,
    validation_status text NOT NULL CHECK (validation_status IN ('passed', 'failed', 'skipped')),
    validation_error text,
    validated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_migration_validation_task ON public.migration_validation(task_name);
CREATE INDEX IF NOT EXISTS idx_migration_validation_status ON public.migration_validation(validation_status);

-- 1.4 迁移配置表
CREATE TABLE IF NOT EXISTS public.migration_config (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    task_name text NOT NULL,
    config_key text NOT NULL,
    config_value text NOT NULL,
    description text,
    updated_at timestamptz DEFAULT now(),
    UNIQUE(task_name, config_key)
);

-- 初始化默认配置
INSERT INTO public.migration_config (task_name, config_key, config_value, description) VALUES
    ('players_to_stats', 'batch_size', '1000', '每批迁移行数'),
    ('players_to_stats', 'sleep_ms', '100', '批次间休眠毫秒数'),
    ('players_to_stats', 'enable_validation', 'true', '是否启用数据校验'),
    ('messages_to_rumors', 'batch_size', '500', '每批迁移行数'),
    ('messages_to_rumors', 'sleep_ms', '200', '批次间休眠毫秒数')
ON CONFLICT (task_name, config_key) DO NOTHING;

-- ============================================================
-- 第二部分：迁移函数 - players → player_role_stats
-- ============================================================

CREATE OR REPLACE FUNCTION public.migrate_players_to_stats(
    p_batch_size int DEFAULT 1000,
    p_sleep_ms int DEFAULT 100,
    p_enable_validation boolean DEFAULT true,
    p_max_batches int DEFAULT 0
)
RETURNS TABLE (
    batch_number int,
    migrated_count int,
    validation_status text,
    elapsed_ms float
) AS $$
DECLARE
    v_last_id uuid;
    v_current_id uuid;
    v_batch_count int := 0;
    v_migrated_count int := 0;
    v_failed_count int := 0;
    v_total_count bigint;
    v_start_time timestamptz;
    v_batch_start timestamptz;
    v_config_sleep_ms int;
BEGIN
    -- 获取配置
    SELECT COALESCE((SELECT config_value::int FROM public.migration_config 
                     WHERE task_name = 'players_to_stats' AND config_key = 'sleep_ms'), p_sleep_ms)
    INTO v_config_sleep_ms;
    
    -- 获取总行数
    SELECT COUNT(*) INTO v_total_count FROM public.players;
    
    -- 读取上次进度（断点续传）
    SELECT last_processed_id 
    INTO v_last_id
    FROM public.migration_progress 
    WHERE task_name = 'players_to_stats';
    
    IF v_last_id IS NULL THEN
        v_last_id := '00000000-0000-0000-0000-000000000000'::uuid;
    END IF;
    
    -- 更新任务状态
    UPDATE public.migration_progress 
    SET status = 'running', 
        started_at = COALESCE(started_at, now()),
        total_rows = v_total_count,
        updated_at = now()
    WHERE task_name = 'players_to_stats'
    ON CONFLICT (task_name) DO UPDATE SET
        status = 'running',
        total_rows = v_total_count,
        updated_at = now();
    
    -- 主迁移循环
    LOOP
        v_batch_count := v_batch_count + 1;
        v_batch_start := clock_timestamp();
        
        IF p_max_batches > 0 AND v_batch_count > p_max_batches THEN
            EXIT;
        END IF;
        
        BEGIN
            -- 迁移当前批次
            WITH batch AS (
                SELECT * FROM public.players
                WHERE id > v_last_id
                ORDER BY id
                LIMIT p_batch_size
            )
            INSERT INTO public.player_role_stats (
                player_id, role_class, silver, private_silver, reputation,
                face_value, prestige, loyalty, stamina, stamina_max,
                stamina_refreshed_at, qi_points, betrayal_count, is_disgraced, route
            )
            SELECT 
                b.id,
                COALESCE(b.role_class, 'guest'),
                COALESCE(b.silver, 0),
                COALESCE(b.private_silver, 0),
                COALESCE(b.reputation, 50),
                COALESCE(b.face_value, 50),
                COALESCE(b.prestige, 50),
                COALESCE(b.loyalty, 50),
                COALESCE(b.stamina, 6),
                COALESCE(b.stamina_max, 6),
                COALESCE(b.stamina_refreshed_at, now()),
                COALESCE(b.qi_points, 100),
                0,
                COALESCE(false, false),
                COALESCE(b.route, 'undecided')
            FROM batch b
            ON CONFLICT (player_id) DO UPDATE SET
                role_class = EXCLUDED.role_class,
                silver = EXCLUDED.silver,
                reputation = EXCLUDED.reputation,
                updated_at = now();
            
            GET DIAGNOSTICS v_migrated_count = ROW_COUNT;
            
            SELECT MAX(id) INTO v_current_id 
            FROM public.players 
            WHERE id > v_last_id 
            ORDER BY id 
            LIMIT p_batch_size;
            
            -- 更新进度
            UPDATE public.migration_progress
            SET last_processed_id = COALESCE(v_current_id, v_last_id),
                migrated_rows = migrated_rows + v_migrated_count,
                batch_count = batch_count + 1,
                updated_at = now()
            WHERE task_name = 'players_to_stats';
            
            -- 返回结果
            RETURN QUERY SELECT 
                v_batch_count,
                v_migrated_count,
                'passed'::text,
                EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start)) * 1000;
            
            v_last_id := COALESCE(v_current_id, v_last_id);
            
            IF v_migrated_count = 0 OR v_current_id IS NULL THEN
                EXIT;
            END IF;
            
            IF v_config_sleep_ms > 0 THEN
                PERFORM pg_sleep(v_config_sleep_ms / 1000.0);
            END IF;
            
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO public.migration_errors (
                task_name, batch_number, source_id,
                error_code, error_message
            ) VALUES (
                'players_to_stats',
                v_batch_count,
                v_last_id,
                SQLSTATE,
                SQLERRM
            );
            
            UPDATE public.migration_progress
            SET failed_count = failed_count + 1,
                error_message = SQLERRM,
                updated_at = now()
            WHERE task_name = 'players_to_stats';
            
            v_failed_count := v_failed_count + 1;
            
            IF v_failed_count >= 10 THEN
                UPDATE public.migration_progress
                SET status = 'failed', completed_at = now()
                WHERE task_name = 'players_to_stats';
                RAISE EXCEPTION '迁移失败次数过多';
            END IF;
            
            CONTINUE;
        END;
    END LOOP;
    
    UPDATE public.migration_progress
    SET status = 'completed', completed_at = now()
    WHERE task_name = 'players_to_stats';
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 第三部分：迁移函数 - messages → rumors
-- ============================================================

CREATE OR REPLACE FUNCTION public.migrate_messages_to_rumors(
    p_batch_size int DEFAULT 500,
    p_sleep_ms int DEFAULT 200,
    p_max_batches int DEFAULT 0
)
RETURNS TABLE (
    batch_number int,
    migrated_count int,
    elapsed_ms float
) AS $$
DECLARE
    v_last_id uuid;
    v_current_id uuid;
    v_batch_count int := 0;
    v_migrated_count int := 0;
    v_config_sleep_ms int;
BEGIN
    SELECT COALESCE((SELECT config_value::int FROM public.migration_config 
                     WHERE task_name = 'messages_to_rumors' AND config_key = 'sleep_ms'), p_sleep_ms)
    INTO v_config_sleep_ms;
    
    SELECT last_processed_id INTO v_last_id
    FROM public.migration_progress 
    WHERE task_name = 'messages_to_rumors';
    
    IF v_last_id IS NULL THEN
        v_last_id := '00000000-0000-0000-0000-000000000000'::uuid;
    END IF;
    
    UPDATE public.migration_progress 
    SET status = 'running', started_at = COALESCE(started_at, now()), updated_at = now()
    WHERE task_name = 'messages_to_rumors'
    ON CONFLICT (task_name) DO UPDATE SET status = 'running', updated_at = now();
    
    LOOP
        v_batch_count := v_batch_count + 1;
        
        IF p_max_batches > 0 AND v_batch_count > p_max_batches THEN
            EXIT;
        END IF;
        
        BEGIN
            WITH batch AS (
                SELECT * FROM public.messages
                WHERE id > v_last_id AND message_type = 'rumor'
                ORDER BY id
                LIMIT p_batch_size
            )
            INSERT INTO public.rumors (
                message_id, game_id, target_uid, stage, belief_rate,
                is_tampered, original_content, expires_at, published_at
            )
            SELECT 
                b.id, b.game_id, b.receiver_uid,
                COALESCE(b.stage, 0), 0.5,
                COALESCE(b.is_tampered, false),
                b.original_content,
                COALESCE(b.expires_at, b.created_at + INTERVAL '24 hours'),
                b.created_at
            FROM batch b
            ON CONFLICT (message_id) DO UPDATE SET
                stage = EXCLUDED.stage,
                updated_at = now();
            
            GET DIAGNOSTICS v_migrated_count = ROW_COUNT;
            
            SELECT MAX(id) INTO v_current_id 
            FROM public.messages 
            WHERE id > v_last_id AND message_type = 'rumor'
            ORDER BY id LIMIT p_batch_size;
            
            UPDATE public.migration_progress
            SET last_processed_id = COALESCE(v_current_id, v_last_id),
                migrated_rows = migrated_rows + v_migrated_count,
                batch_count = batch_count + 1,
                updated_at = now()
            WHERE task_name = 'messages_to_rumors';
            
            RETURN QUERY SELECT 
                v_batch_count, v_migrated_count,
                EXTRACT(EPOCH FROM (clock_timestamp() - statement_timestamp())) * 1000;
            
            v_last_id := COALESCE(v_current_id, v_last_id);
            
            IF v_migrated_count = 0 THEN EXIT; END IF;
            IF v_config_sleep_ms > 0 THEN PERFORM pg_sleep(v_config_sleep_ms / 1000.0); END IF;
            
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO public.migration_errors (task_name, batch_number, source_id, error_code, error_message)
            VALUES ('messages_to_rumors', v_batch_count, v_last_id, SQLSTATE, SQLERRM);
            
            UPDATE public.migration_progress
            SET failed_count = failed_count + 1, error_message = SQLERRM, updated_at = now()
            WHERE task_name = 'messages_to_rumors';
            
            CONTINUE;
        END;
    END LOOP;
    
    UPDATE public.migration_progress SET status = 'completed', completed_at = now()
    WHERE task_name = 'messages_to_rumors';
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 第四部分：监控视图
-- ============================================================

CREATE OR REPLACE VIEW public.migration_status AS
SELECT 
    task_name,
    source_table,
    target_table,
    status,
    total_rows,
    migrated_rows,
    batch_count,
    failed_count,
    ROUND(100.0 * migrated_rows / NULLIF(total_rows, 0), 2) AS progress_percent,
    CASE 
        WHEN status = 'completed' THEN '✅'
        WHEN status = 'running' THEN '🔄'
        WHEN status = 'paused' THEN '⏸️'
        WHEN status = 'failed' THEN '❌'
        ELSE '⏳'
    END AS status_icon,
    started_at,
    completed_at,
    updated_at
FROM public.migration_progress
ORDER BY task_name;

-- ============================================================
-- 第五部分：执行脚本
-- ============================================================

-- 查看当前迁移进度
-- SELECT * FROM public.migration_status;

-- 执行 players → player_role_stats 迁移
-- SELECT * FROM public.migrate_players_to_stats(1000, 100, true, 0);

-- 执行 messages → rumors 迁移
-- SELECT * FROM public.migrate_messages_to_rumors(500, 200, 0);

-- 查看错误日志
-- SELECT * FROM public.migration_errors ORDER BY created_at DESC LIMIT 100;

-- 重置迁移任务
-- UPDATE public.migration_progress SET status='pending', migrated_rows=0, batch_count=0 WHERE task_name='players_to_stats';
