-- ============================================================
-- 《红楼回忆志》完整数据库初始化脚本
-- 适用于 Supabase SQL Editor
-- 执行顺序：先执行 SECTION 1-5 创建架构，再执行 SECTION 6 插入测试数据
-- ============================================================

-- ============================================================
-- SECTION 1: 基础设置与扩展
-- ============================================================

-- 启用必要的扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 通用更新时间触发器函数
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- SECTION 2: 枚举类型定义
-- ============================================================

DO $$
BEGIN
    -- 管家路线
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'steward_route') THEN
        CREATE TYPE steward_route AS ENUM ('virtuous', 'schemer', 'undecided');
    END IF;

    -- 行动类型
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'action_type') THEN
        CREATE TYPE action_type AS ENUM ('procurement', 'assignment', 'search', 'advance', 'suppress_rumor', 'block_intel');
    END IF;

    -- 审批状态
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'approval_status') THEN
        CREATE TYPE approval_status AS ENUM ('pending', 'executed', 'cancelled');
    END IF;

    -- 查账状态
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'audit_status') THEN
        CREATE TYPE audit_status AS ENUM ('filed', 'investigating', 'concluded');
    END IF;

    -- 查账结论
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'audit_verdict') THEN
        CREATE TYPE audit_verdict AS ENUM ('acquitted', 'demoted', 'catastrophe');
    END IF;

    -- 情报类型
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'intel_type') THEN
        CREATE TYPE intel_type AS ENUM (
            'account_leak', 'private_action', 'gift_record', 'visitor_info', 'elder_favor'
        );
    END IF;

    -- 场景地点
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'scene_location') THEN
        CREATE TYPE scene_location AS ENUM (
            'yi_hong_yuan', 'treasury_back', 'bridge', 'gate', 'elder_room'
        );
    END IF;

    -- 会话状态
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'session_status') THEN
        CREATE TYPE session_status AS ENUM ('active', 'completed', 'interrupted');
    END IF;

    -- 消息状态
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_status') THEN
        CREATE TYPE message_status AS ENUM ('pending', 'delivered', 'intercepted', 'tampered');
    END IF;

    -- 交易状态
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'trade_status') THEN
        CREATE TYPE trade_status AS ENUM ('pending', 'completed', 'cancelled');
    END IF;

    -- 丫鬟关系类型
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'maid_relation_type') THEN
        CREATE TYPE maid_relation_type AS ENUM ('dui_shi', 'si_yue');
    END IF;

    -- 丫鬟关系状态
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'maid_relation_status') THEN
        CREATE TYPE maid_relation_status AS ENUM ('pending', 'active', 'betrayed', 'dissolved');
    END IF;
END $$;

-- ============================================================
-- SECTION 3: 核心表结构
-- ============================================================

-- 游戏局表
CREATE TABLE IF NOT EXISTS public.games (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    start_timestamp BIGINT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    speed_multiplier FLOAT DEFAULT 1.0,
    deficit_value FLOAT DEFAULT 0.0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 玩家表
CREATE TABLE IF NOT EXISTS public.players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_uid UUID NOT NULL UNIQUE,
    username TEXT NOT NULL,
    display_name TEXT,
    character_name TEXT,
    role_class TEXT NOT NULL CHECK (role_class IN ('steward', 'master', 'servant', 'elder', 'guest')),
    current_game_id UUID REFERENCES public.games(id),
    stamina INT DEFAULT 6,
    stamina_max INT DEFAULT 6,
    stamina_refreshed_at TIMESTAMPTZ DEFAULT NOW(),
    private_silver INT DEFAULT 0,
    qi_points INT DEFAULT 100,
    face_value INT DEFAULT 50,
    prestige INT DEFAULT 10,
    loyalty INT DEFAULT 50,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 银库表
CREATE TABLE IF NOT EXISTS public.treasury (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id),
    total_silver INT DEFAULT 50000,
    daily_budget INT DEFAULT 2000,
    public_balance INT DEFAULT 50000,
    real_balance INT DEFAULT 50000,
    prosperity_level INT DEFAULT 8,
    deficit_rate FLOAT DEFAULT 0.0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 管家账本表
CREATE TABLE IF NOT EXISTS public.steward_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL,
    steward_uid UUID NOT NULL REFERENCES public.players(id),
    public_ledger JSONB DEFAULT '[]'::jsonb,
    private_assets INT DEFAULT 0,
    private_ledger JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(game_id, steward_uid)
);

-- 流言表
CREATE TABLE IF NOT EXISTS public.rumors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id),
    publisher_uid UUID NOT NULL REFERENCES public.players(id),
    target_uid UUID NOT NULL REFERENCES public.players(id),
    content TEXT NOT NULL,
    source_type TEXT,
    intel_fragment_ids UUID[],
    is_grafted BOOLEAN DEFAULT FALSE,
    credibility FLOAT DEFAULT 1.0,
    stage INT DEFAULT 1 CHECK (stage BETWEEN 1 AND 3),
    published_at TIMESTAMPTZ DEFAULT NOW(),
    stage2_at TIMESTAMPTZ,
    stage3_at TIMESTAMPTZ,
    is_suppressed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 流言事件表
CREATE TABLE IF NOT EXISTS public.rumor_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rumor_id UUID NOT NULL REFERENCES public.rumors(id),
    actor_uid UUID NOT NULL REFERENCES public.players(id),
    event_type TEXT NOT NULL,
    event_data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 情报碎片表
CREATE TABLE IF NOT EXISTS public.intel_fragments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id),
    intel_type TEXT NOT NULL,
    content TEXT NOT NULL,
    source_uid UUID REFERENCES public.players(id),
    owner_uid UUID NOT NULL REFERENCES public.players(id),
    about_player_id UUID REFERENCES public.players(id),
    scene TEXT,
    is_used BOOLEAN DEFAULT FALSE,
    is_blocked BOOLEAN DEFAULT FALSE,
    blocked_until TIMESTAMPTZ,
    blocked_by UUID REFERENCES public.players(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 消息表
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id),
    sender_uid UUID NOT NULL REFERENCES public.players(id),
    receiver_uid UUID REFERENCES public.players(id),
    carrier_uid UUID REFERENCES public.players(id),
    message_type TEXT NOT NULL,
    content TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 月例记录表
CREATE TABLE IF NOT EXISTS public.allowance_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id),
    issued_by UUID NOT NULL REFERENCES public.players(id),
    player_id UUID NOT NULL REFERENCES public.players(id),
    amount_public INT NOT NULL,
    amount_actual INT NOT NULL,
    withheld_amount INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 账本条目表
CREATE TABLE IF NOT EXISTS public.ledger_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id),
    treasury_id UUID REFERENCES public.treasury(id),
    ledger_type TEXT NOT NULL CHECK (ledger_type IN ('public', 'private')),
    entry_type TEXT NOT NULL,
    amount INT NOT NULL,
    actor_id UUID NOT NULL REFERENCES public.players(id),
    target_id UUID REFERENCES public.players(id),
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 亏空日志表
CREATE TABLE IF NOT EXISTS public.deficit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id),
    deficit_value FLOAT NOT NULL,
    trigger_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 采办票表
CREATE TABLE IF NOT EXISTS public.procurement_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id),
    steward_uid UUID NOT NULL REFERENCES public.players(id),
    item_template_key TEXT NOT NULL,
    quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','used','cancelled')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    used_at TIMESTAMPTZ
);

-- ============================================================
-- SECTION 4: 辅助函数
-- ============================================================

-- 获取当前玩家 ID
CREATE OR REPLACE FUNCTION public.get_my_player_id()
RETURNS UUID AS $$
BEGIN
    RETURN (
        SELECT id FROM public.players
        WHERE auth_uid = auth.uid()
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 更新时间触发器
CREATE TRIGGER update_games_updated_at BEFORE UPDATE ON public.games
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_players_updated_at BEFORE UPDATE ON public.players
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_treasury_updated_at BEFORE UPDATE ON public.treasury
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_steward_accounts_updated_at BEFORE UPDATE ON public.steward_accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- SECTION 5: RLS 权限策略（完整修复版）
-- ============================================================

-- 启用所有表的 RLS
ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treasury ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.steward_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rumors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rumor_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intel_fragments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.allowance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deficit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.procurement_tickets ENABLE ROW LEVEL SECURITY;

-- 删除旧策略
DROP POLICY IF EXISTS "authenticated_select_games" ON public.games;
DROP POLICY IF EXISTS "authenticated_insert_games" ON public.games;
DROP POLICY IF EXISTS "authenticated_update_games" ON public.games;
DROP POLICY IF EXISTS "authenticated_select_players" ON public.players;
DROP POLICY IF EXISTS "authenticated_insert_players" ON public.players;
DROP POLICY IF EXISTS "authenticated_update_players" ON public.players;
DROP POLICY IF EXISTS "authenticated_select_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_insert_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_update_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_select_rumor_events" ON public.rumor_events;
DROP POLICY IF EXISTS "authenticated_insert_rumor_events" ON public.rumor_events;
DROP POLICY IF EXISTS "authenticated_select_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_insert_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_update_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_select_messages" ON public.messages;
DROP POLICY IF EXISTS "authenticated_insert_messages" ON public.messages;
DROP POLICY IF EXISTS "authenticated_update_messages" ON public.messages;
DROP POLICY IF EXISTS "authenticated_select_steward_accounts" ON public.steward_accounts;
DROP POLICY IF EXISTS "authenticated_insert_steward_accounts" ON public.steward_accounts;
DROP POLICY IF EXISTS "authenticated_update_steward_accounts" ON public.steward_accounts;
DROP POLICY IF EXISTS "authenticated_select_treasury" ON public.treasury;
DROP POLICY IF EXISTS "authenticated_insert_treasury" ON public.treasury;
DROP POLICY IF EXISTS "authenticated_update_treasury" ON public.treasury;
DROP POLICY IF EXISTS "authenticated_select_allowance_records" ON public.allowance_records;
DROP POLICY IF EXISTS "authenticated_insert_allowance_records" ON public.allowance_records;
DROP POLICY IF EXISTS "authenticated_select_ledger_entries" ON public.ledger_entries;
DROP POLICY IF EXISTS "authenticated_insert_ledger_entries" ON public.ledger_entries;
DROP POLICY IF EXISTS "authenticated_select_deficit_log" ON public.deficit_log;
DROP POLICY IF EXISTS "authenticated_insert_deficit_log" ON public.deficit_log;
DROP POLICY IF EXISTS "authenticated_select_procurement_tickets" ON public.procurement_tickets;
DROP POLICY IF EXISTS "authenticated_insert_procurement_tickets" ON public.procurement_tickets;
DROP POLICY IF EXISTS "authenticated_update_procurement_tickets" ON public.procurement_tickets;
DROP POLICY IF EXISTS "authenticated_delete_procurement_tickets" ON public.procurement_tickets;

-- 创建新策略 - games
CREATE POLICY "authenticated_select_games" ON public.games FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_games" ON public.games FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_games" ON public.games FOR UPDATE TO authenticated USING (true);

-- 创建新策略 - players
CREATE POLICY "authenticated_select_players" ON public.players FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_players" ON public.players FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_players" ON public.players FOR UPDATE TO authenticated USING (true);

-- 创建新策略 - rumors（核心修复）
CREATE POLICY "authenticated_select_rumors" ON public.rumors FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_rumors" ON public.rumors FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_rumors" ON public.rumors FOR UPDATE TO authenticated USING (true);

-- 创建新策略 - rumor_events
CREATE POLICY "authenticated_select_rumor_events" ON public.rumor_events FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_rumor_events" ON public.rumor_events FOR INSERT TO authenticated WITH CHECK (true);

-- 创建新策略 - intel_fragments
CREATE POLICY "authenticated_select_intel_fragments" ON public.intel_fragments FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_intel_fragments" ON public.intel_fragments FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_intel_fragments" ON public.intel_fragments FOR UPDATE TO authenticated USING (true);

-- 创建新策略 - messages
CREATE POLICY "authenticated_select_messages" ON public.messages FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_messages" ON public.messages FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_messages" ON public.messages FOR UPDATE TO authenticated USING (true);

-- 创建新策略 - steward_accounts
CREATE POLICY "authenticated_select_steward_accounts" ON public.steward_accounts FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_steward_accounts" ON public.steward_accounts FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_steward_accounts" ON public.steward_accounts FOR UPDATE TO authenticated USING (true);

-- 创建新策略 - treasury
CREATE POLICY "authenticated_select_treasury" ON public.treasury FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_treasury" ON public.treasury FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_treasury" ON public.treasury FOR UPDATE TO authenticated USING (true);

-- 创建新策略 - allowance_records
CREATE POLICY "authenticated_select_allowance_records" ON public.allowance_records FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_allowance_records" ON public.allowance_records FOR INSERT TO authenticated WITH CHECK (true);

-- 创建新策略 - ledger_entries
CREATE POLICY "authenticated_select_ledger_entries" ON public.ledger_entries FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_ledger_entries" ON public.ledger_entries FOR INSERT TO authenticated WITH CHECK (true);

-- 创建新策略 - deficit_log
CREATE POLICY "authenticated_select_deficit_log" ON public.deficit_log FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_deficit_log" ON public.deficit_log FOR INSERT TO authenticated WITH CHECK (true);

-- 创建新策略 - procurement_tickets
CREATE POLICY "authenticated_select_procurement_tickets" ON public.procurement_tickets FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_procurement_tickets" ON public.procurement_tickets FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_procurement_tickets" ON public.procurement_tickets FOR UPDATE TO authenticated USING (true);
CREATE POLICY "authenticated_delete_procurement_tickets" ON public.procurement_tickets FOR DELETE TO authenticated USING (true);

-- ============================================================
-- SECTION 6: 管家 RPC 函数
-- ============================================================

-- 发放月例 RPC
CREATE OR REPLACE FUNCTION public.distribute_allowance_rpc(
    p_steward_uid uuid,
    p_recipient_uid uuid,
    p_recipient_name text,
    p_actual_amount int,
    p_standard_amount int,
    p_game_id uuid
)
RETURNS json AS $$
DECLARE
    v_treasury_id uuid;
    v_total_silver int;
    v_withheld int;
    v_public_entry jsonb;
    v_private_entry jsonb;
    v_withheld_count int;
BEGIN
    SELECT id, total_silver INTO v_treasury_id, v_total_silver
    FROM public.treasury WHERE game_id = p_game_id;

    IF v_treasury_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', '未找到银库数据');
    END IF;

    IF v_total_silver < p_actual_amount THEN
        RETURN json_build_object('success', false, 'error', '银库余额不足');
    END IF;

    v_withheld := p_standard_amount - p_actual_amount;

    UPDATE public.treasury SET total_silver = total_silver - p_actual_amount, updated_at = now()
    WHERE id = v_treasury_id;

    UPDATE public.players SET private_silver = private_silver + p_actual_amount, updated_at = now()
    WHERE id = p_recipient_uid;

    v_public_entry := json_build_object('type', 'allowance', 'recipient_uid', p_recipient_uid,
        'recipient_name', p_recipient_name, 'amount', p_actual_amount, 'timestamp', now());

    INSERT INTO public.steward_accounts (game_id, steward_uid, public_ledger, updated_at)
    VALUES (p_game_id, p_steward_uid, jsonb_build_array(v_public_entry), now())
    ON CONFLICT (game_id, steward_uid) DO UPDATE
    SET public_ledger = public.steward_accounts.public_ledger || v_public_entry, updated_at = now();

    INSERT INTO public.ledger_entries (game_id, treasury_id, ledger_type, entry_type, amount, actor_id, target_id, note)
    VALUES (p_game_id, v_treasury_id, 'public', 'allocation', p_actual_amount, p_steward_uid, p_recipient_uid,
        '发放月例：' || p_actual_amount || ' 两');

    IF v_withheld > 0 THEN
        v_private_entry := json_build_object('type', 'embezzlement', 'recipient_uid', p_recipient_uid,
            'recipient_name', p_recipient_name, 'standard', p_standard_amount, 'actual', p_actual_amount,
            'withheld', v_withheld, 'timestamp', now());

        INSERT INTO public.steward_accounts (game_id, steward_uid, private_assets, private_ledger, updated_at)
        VALUES (p_game_id, p_steward_uid, v_withheld, jsonb_build_array(v_private_entry), now())
        ON CONFLICT (game_id, steward_uid) DO UPDATE
        SET private_assets = public.steward_accounts.private_assets + v_withheld,
            private_ledger = public.steward_accounts.private_ledger || v_private_entry, updated_at = now();

        INSERT INTO public.ledger_entries (game_id, treasury_id, ledger_type, entry_type, amount, actor_id, target_id, note)
        VALUES (p_game_id, v_treasury_id, 'private', 'allocation', v_withheld, p_steward_uid, p_recipient_uid,
            '克扣月例：' || v_withheld || ' 两');
    END IF;

    SELECT COUNT(*) INTO v_withheld_count FROM public.allowance_records
    WHERE game_id = p_game_id AND withheld_amount > 0;

    IF v_withheld_count >= 3 THEN
        INSERT INTO public.intel_fragments (game_id, intel_type, content, source_uid, owner_uid, scene)
        VALUES (p_game_id, 'account_leak', '府中已有三名下人因月例被扣私下议论，管家账目恐有疏漏。',
            p_steward_uid, p_steward_uid, 'treasury_back');
    END IF;

    RETURN json_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 批量发放月例 RPC
CREATE OR REPLACE FUNCTION public.bulk_distribute_allowance_rpc(
    p_steward_uid uuid,
    p_game_id uuid,
    p_distributions jsonb
)
RETURNS json AS $$
DECLARE
    v_dist jsonb;
    v_res json;
    v_total_distributed int := 0;
BEGIN
    FOR v_dist IN SELECT * FROM jsonb_array_elements(p_distributions) LOOP
        v_res := public.distribute_allowance_rpc(
            p_steward_uid, (v_dist->>'recipient_uid')::uuid, v_dist->>'recipient_name',
            (v_dist->>'actual_amount')::int, (v_dist->>'standard_amount')::int, p_game_id);

        IF NOT (v_res->>'success')::boolean THEN
            RAISE EXCEPTION '发放失败：%s', v_res->>'error';
        END IF;

        v_total_distributed := v_total_distributed + (v_dist->>'actual_amount')::int;
    END LOOP;

    RETURN json_build_object('success', true, 'total_distributed', v_total_distributed);
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 获取银库统计 RPC
CREATE OR REPLACE FUNCTION public.get_treasury_stats(p_game_id uuid)
RETURNS TABLE(sum_public bigint, sum_withheld bigint) AS $$
BEGIN
    RETURN QUERY
    SELECT COALESCE(SUM(amount_public)::bigint, 0), COALESCE(SUM(withheld_amount)::bigint, 0)
    FROM public.allowance_records WHERE game_id = p_game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 管家平息流言 RPC
CREATE OR REPLACE FUNCTION public.steward_suppress_rumor(p_rumor_id uuid)
RETURNS json AS $$
DECLARE
    v_rumor record;
    v_steward_id uuid;
BEGIN
    -- 获取当前管家 ID
    SELECT id INTO v_steward_id FROM public.players WHERE auth_uid = auth.uid() AND role_class = 'steward';
    
    IF v_steward_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', '只有管家可以执行此操作');
    END IF;

    -- 获取流言信息
    SELECT * INTO v_rumor FROM public.rumors WHERE id = p_rumor_id;
    
    IF v_rumor IS NULL THEN
        RETURN json_build_object('success', false, 'error', '流言不存在');
    END IF;

    -- 更新流言状态
    UPDATE public.rumors SET is_suppressed = true WHERE id = p_rumor_id;

    RETURN json_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 授予执行权限
GRANT EXECUTE ON FUNCTION public.distribute_allowance_rpc TO authenticated;
GRANT EXECUTE ON FUNCTION public.bulk_distribute_allowance_rpc TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_treasury_stats TO authenticated;
GRANT EXECUTE ON FUNCTION public.steward_suppress_rumor TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_player_id TO authenticated;

-- ============================================================
-- SECTION 7: 测试数据
-- ============================================================

-- 创建测试游戏局
INSERT INTO public.games (id, start_timestamp, status, speed_multiplier, deficit_value)
VALUES ('00000000-0000-0000-0000-000000000001', extract(epoch from now())::bigint, 'active', 1.0, 0.0)
ON CONFLICT (id) DO UPDATE SET status = 'active';

-- 创建测试银库
INSERT INTO public.treasury (game_id, total_silver, daily_budget, public_balance, real_balance, prosperity_level, deficit_rate)
VALUES ('00000000-0000-0000-0000-000000000001', 50000, 2000, 50000, 50000, 8, 0.0)
ON CONFLICT (game_id) DO UPDATE SET total_silver = EXCLUDED.total_silver;

-- ============================================================
-- 初始化完成
-- ============================================================
