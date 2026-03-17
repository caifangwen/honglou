-- ============================================================
-- 《红楼回忆志》数据库架构文件
-- 版本：2026-03-17
-- 使用方法：在 Supabase SQL Editor 中执行
-- ============================================================

-- ============================================================
-- SECTION 1: 基础设置与扩展
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 创建 anon 角色（本地开发环境需要）
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon WITH LOGIN;
    END IF;
END $$;

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
        CREATE TYPE session_status AS ENUM ('active', 'completed', 'interrupted', 'cancelled');
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

    -- 关系类型
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'relation_type') THEN
        CREATE TYPE relation_type AS ENUM ('ally', 'rival', 'confidant', 'admirer', 'duo_wiretap', 'betrayed');
    END IF;
END $$;

-- ============================================================
-- SECTION 3: 核心表结构
-- ============================================================

-- 游戏局表
CREATE TABLE IF NOT EXISTS public.games (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    status text DEFAULT 'active' CHECK (status IN ('active', 'crisis', 'purge', 'ended')),
    start_timestamp bigint NOT NULL,
    end_timestamp bigint,
    speed_multiplier float DEFAULT 1.0,
    deficit_value float DEFAULT 0.0,
    conflict_value float DEFAULT 0.0,
    current_day int DEFAULT 1,
    started_at timestamptz DEFAULT now(),
    ended_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- 玩家表
CREATE TABLE IF NOT EXISTS public.players (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_uid uuid UNIQUE NOT NULL,
    username text UNIQUE,
    display_name text NOT NULL,
    character_name text,
    role_class text NOT NULL CHECK (role_class IN ('steward', 'master', 'servant', 'elder', 'guest')),
    current_game_id uuid REFERENCES public.games(id),
    stamina int DEFAULT 6,
    stamina_max int DEFAULT 6,
    stamina_refreshed_at timestamptz DEFAULT now(),
    qi_points int DEFAULT 100,
    silver int DEFAULT 0,
    private_silver int DEFAULT 0,
    reputation int DEFAULT 50,
    face_value int DEFAULT 50,
    prestige int DEFAULT 50,
    loyalty int DEFAULT 50,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- 管家精力表
CREATE TABLE IF NOT EXISTS public.steward_stamina (
    uid uuid PRIMARY KEY REFERENCES public.players(id),
    current_stamina int DEFAULT 6,
    max_stamina int DEFAULT 6,
    last_refresh_at timestamptz DEFAULT now()
);

-- 银库表
CREATE TABLE IF NOT EXISTS public.treasury (
    game_id uuid PRIMARY KEY REFERENCES public.games(id),
    total_silver int DEFAULT 50000,
    daily_budget int DEFAULT 2000,
    public_balance int DEFAULT 50000,
    real_balance int DEFAULT 50000,
    prosperity_level int DEFAULT 8,
    deficit_rate float DEFAULT 0.0,
    last_update timestamptz DEFAULT now()
);

-- 管家账本表
CREATE TABLE IF NOT EXISTS public.steward_accounts (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL REFERENCES public.games(id),
    steward_uid uuid NOT NULL REFERENCES public.players(id),
    public_ledger jsonb DEFAULT '[]'::jsonb,
    private_ledger jsonb DEFAULT '[]'::jsonb,
    private_assets int DEFAULT 0,
    prestige int DEFAULT 50,
    route steward_route DEFAULT 'undecided',
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(game_id, steward_uid)
);

-- 账本条目表
CREATE TABLE IF NOT EXISTS public.ledger_entries (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL REFERENCES public.games(id),
    treasury_id uuid REFERENCES public.treasury(game_id),
    actor_id uuid NOT NULL REFERENCES public.players(id),
    target_id uuid REFERENCES public.players(id),
    ledger_type text DEFAULT 'public' CHECK (ledger_type IN ('public', 'private')),
    entry_type text DEFAULT 'allocation' CHECK (entry_type IN ('allocation', 'procurement', 'advance', 'other')),
    amount int DEFAULT 0,
    note text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- 月例发放记录表
CREATE TABLE IF NOT EXISTS public.allowance_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    player_id uuid REFERENCES public.players(id),
    issued_by uuid REFERENCES public.players(id),
    amount_public int NOT NULL,
    amount_actual int NOT NULL,
    withheld_amount int DEFAULT 0,
    is_public boolean DEFAULT true,
    issued_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now()
);

-- 采办物资票据表
CREATE TABLE IF NOT EXISTS public.procurement_tickets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    steward_uid uuid NOT NULL REFERENCES public.players(id),
    item_template_key text NOT NULL,
    quantity int NOT NULL DEFAULT 1 CHECK (quantity > 0),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','used','cancelled')),
    created_at timestamptz DEFAULT now(),
    used_at timestamptz
);

-- 行动批条表
CREATE TABLE IF NOT EXISTS public.action_approvals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id),
    steward_uid uuid NOT NULL REFERENCES public.players(id),
    action_type text NOT NULL,
    target_id uuid REFERENCES public.players(id),
    stamina_cost int NOT NULL,
    params jsonb DEFAULT '{}',
    status text DEFAULT 'pending' CHECK (status IN ('pending', 'executed', 'cancelled')),
    executed_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- 流言表
CREATE TABLE IF NOT EXISTS public.rumors (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL REFERENCES public.games(id),
    owner_uid uuid NOT NULL REFERENCES public.players(id),
    source_uid uuid REFERENCES public.players(id),
    target_uid uuid REFERENCES public.players(id),
    content text NOT NULL,
    stage int DEFAULT 1 CHECK (stage BETWEEN 1 AND 4),
    spread_count int DEFAULT 0,
    belief_rate float DEFAULT 0.5,
    status text DEFAULT 'active' CHECK (status IN ('active', 'suppressed', 'expired')),
    created_at timestamptz DEFAULT now(),
    expires_at timestamptz DEFAULT (now() + INTERVAL '24 hours')
);

-- 消息表
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL REFERENCES public.games(id),
    sender_uid uuid NOT NULL REFERENCES public.players(id),
    receiver_uid uuid NOT NULL REFERENCES public.players(id),
    content text NOT NULL,
    status message_status DEFAULT 'pending',
    is_read boolean DEFAULT FALSE,
    created_at timestamptz DEFAULT now(),
    read_at timestamptz
);

-- ============================================================
-- SECTION 4: 听壁脚系统表
-- ============================================================

-- 挂机监听会话表
CREATE TABLE IF NOT EXISTS public.eavesdrop_sessions (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL REFERENCES public.games(id),
    player_uid uuid NOT NULL REFERENCES public.players(id),
    scene scene_location NOT NULL,
    scene_key text NOT NULL,
    partner_uid uuid REFERENCES public.players(id),
    is_duo boolean DEFAULT FALSE,
    success_rate_mod real DEFAULT 1.0,
    starts_at timestamptz DEFAULT now(),
    ends_at timestamptz NOT NULL,
    status session_status DEFAULT 'active',
    result_count int DEFAULT 0,
    created_at timestamptz DEFAULT now()
);

-- 情报碎片表
CREATE TABLE IF NOT EXISTS public.intel_fragments (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL REFERENCES public.games(id),
    owner_uid uuid NOT NULL REFERENCES public.players(id),
    source_uid uuid REFERENCES public.players(id),
    session_id uuid REFERENCES public.eavesdrop_sessions(id),
    content text NOT NULL,
    intel_type intel_type NOT NULL,
    scene text,
    scene_key text,
    value_level int DEFAULT 1 CHECK (value_level BETWEEN 1 AND 5),
    status text DEFAULT 'unread' CHECK (status IN ('unread', 'read', 'used')),
    is_used boolean DEFAULT FALSE,
    is_sold boolean DEFAULT FALSE,
    obtained_at timestamptz DEFAULT now(),
    expires_at timestamptz DEFAULT (now() + INTERVAL '48 hours'),
    created_at timestamptz DEFAULT now()
);

-- 情报交易表
CREATE TABLE IF NOT EXISTS public.intel_trades (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL REFERENCES public.games(id),
    seller_uid uuid NOT NULL REFERENCES public.players(id),
    buyer_uid uuid NOT NULL REFERENCES public.players(id),
    fragment_id uuid NOT NULL REFERENCES public.intel_fragments(id),
    price_silver int DEFAULT 0,
    price_qi int DEFAULT 0,
    status trade_status DEFAULT 'pending',
    traded_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- 情报拦截表
CREATE TABLE IF NOT EXISTS public.intel_intercepts (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL REFERENCES public.games(id),
    interceptor_uid uuid NOT NULL REFERENCES public.players(id),
    target_uid uuid NOT NULL REFERENCES public.players(id),
    starts_at timestamptz DEFAULT now(),
    ends_at timestamptz NOT NULL,
    status text DEFAULT 'active' CHECK (status IN ('active', 'expired', 'cancelled')),
    created_at timestamptz DEFAULT now()
);

-- ============================================================
-- SECTION 5: 社交关系表
-- ============================================================

-- 核心关系网表
CREATE TABLE IF NOT EXISTS public.relationships (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL REFERENCES public.games(id),
    player_a uuid NOT NULL REFERENCES public.players(id),
    player_b uuid NOT NULL REFERENCES public.players(id),
    relation_type text NOT NULL CHECK (relation_type IN ('ally', 'rival', 'confidant', 'admirer', 'duo_wiretap', 'betrayed')),
    initiated_by uuid REFERENCES public.players(id),
    is_mutual boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(game_id, player_a, player_b, relation_type)
);

-- 丫鬟关系表
CREATE TABLE IF NOT EXISTS public.maid_relationships (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL REFERENCES public.games(id),
    player_a_uid uuid NOT NULL REFERENCES public.players(id),
    player_b_uid uuid NOT NULL REFERENCES public.players(id),
    relation_type maid_relation_type NOT NULL,
    status maid_relation_status DEFAULT 'pending',
    initiated_by uuid REFERENCES public.players(id),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(game_id, player_a_uid, player_b_uid, relation_type)
);

-- 丫鬟关系申请表
CREATE TABLE IF NOT EXISTS public.servant_relationships (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL REFERENCES public.games(id),
    servant_a uuid NOT NULL REFERENCES public.players(id),
    servant_b uuid NOT NULL REFERENCES public.players(id),
    relation_type text NOT NULL,
    status text DEFAULT 'pending',
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- ============================================================
-- SECTION 6: 索引
-- ============================================================

-- eavesdrop_sessions 索引
CREATE INDEX IF NOT EXISTS idx_eavesdrop_sessions_active ON public.eavesdrop_sessions(game_id, status, scene_key);
CREATE INDEX IF NOT EXISTS idx_eavesdrop_sessions_player ON public.eavesdrop_sessions(player_uid, status);
CREATE INDEX IF NOT EXISTS idx_eavesdrop_sessions_scene ON public.eavesdrop_sessions(game_id, scene_key, status);

-- intel_fragments 索引
CREATE INDEX IF NOT EXISTS idx_intel_fragments_owner ON public.intel_fragments(owner_uid, is_sold, is_used, expires_at);
CREATE INDEX IF NOT EXISTS idx_intel_fragments_session ON public.intel_fragments(session_id);
CREATE INDEX IF NOT EXISTS idx_intel_fragments_game ON public.intel_fragments(game_id);
CREATE INDEX IF NOT EXISTS idx_intel_fragments_scene ON public.intel_fragments(scene);

-- intel_intercepts 索引
CREATE INDEX IF NOT EXISTS idx_intel_intercepts_target ON public.intel_intercepts(target_uid, status, ends_at);
CREATE INDEX IF NOT EXISTS idx_intel_intercepts_game ON public.intel_intercepts(game_id, status);

-- ============================================================
-- SECTION 9: 辅助函数（听壁脚系统）
-- ============================================================

-- 获取当前玩家 ID
CREATE OR REPLACE FUNCTION public.get_my_player_id()
RETURNS uuid AS $$
BEGIN
    RETURN (
        SELECT id FROM public.players
        WHERE auth_uid = auth.uid()
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 获取会话剩余时间
CREATE OR REPLACE FUNCTION public.get_session_remaining_time(p_session_id uuid)
RETURNS integer AS $$
DECLARE
    v_ends_at timestamptz;
    v_remaining integer;
BEGIN
    SELECT ends_at INTO v_ends_at
    FROM public.eavesdrop_sessions
    WHERE id = p_session_id;
    
    IF NOT FOUND THEN
        RETURN 0;
    END IF;
    
    v_remaining := EXTRACT(EPOCH FROM (v_ends_at - NOW()))::integer;
    RETURN GREATEST(0, v_remaining);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 获取玩家活跃会话数
CREATE OR REPLACE FUNCTION public.get_player_active_session_count(p_player_uid uuid)
RETURNS integer AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM public.eavesdrop_sessions
        WHERE player_uid = p_player_uid
        AND status = 'active'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 获取场景监听人数
CREATE OR REPLACE FUNCTION public.get_scene_listener_count(p_game_id uuid, p_scene_key text)
RETURNS integer AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM public.eavesdrop_sessions
        WHERE game_id = p_game_id
        AND scene_key = p_scene_key
        AND status = 'active'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 检查玩家是否被拦截
CREATE OR REPLACE FUNCTION public.is_player_intercepted(p_player_uid uuid)
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.intel_intercepts
        WHERE target_uid = p_player_uid
        AND status = 'active'
        AND ends_at > NOW()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- SECTION 8: RLS 策略
-- ============================================================

-- 启用 RLS
ALTER TABLE public.eavesdrop_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intel_fragments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intel_trades ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intel_intercepts ENABLE ROW LEVEL SECURITY;

-- eavesdrop_sessions 策略
DROP POLICY IF EXISTS "authenticated_select_eavesdrop_sessions" ON public.eavesdrop_sessions;
DROP POLICY IF EXISTS "authenticated_insert_eavesdrop_sessions" ON public.eavesdrop_sessions;
DROP POLICY IF EXISTS "authenticated_update_eavesdrop_sessions" ON public.eavesdrop_sessions;

CREATE POLICY "authenticated_select_eavesdrop_sessions" ON public.eavesdrop_sessions
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_eavesdrop_sessions" ON public.eavesdrop_sessions
    FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_eavesdrop_sessions" ON public.eavesdrop_sessions
    FOR UPDATE TO authenticated USING (true);

-- intel_fragments 策略
DROP POLICY IF EXISTS "authenticated_select_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_insert_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_update_intel_fragments" ON public.intel_fragments;

CREATE POLICY "authenticated_select_intel_fragments" ON public.intel_fragments
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_intel_fragments" ON public.intel_fragments
    FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_intel_fragments" ON public.intel_fragments
    FOR UPDATE TO authenticated USING (true);

-- intel_trades 策略
DROP POLICY IF EXISTS "authenticated_select_intel_trades" ON public.intel_trades;
DROP POLICY IF EXISTS "authenticated_insert_intel_trades" ON public.intel_trades;
DROP POLICY IF EXISTS "authenticated_update_intel_trades" ON public.intel_trades;

CREATE POLICY "authenticated_select_intel_trades" ON public.intel_trades
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_intel_trades" ON public.intel_trades
    FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_intel_trades" ON public.intel_trades
    FOR UPDATE TO authenticated USING (true);

-- intel_intercepts 策略
DROP POLICY IF EXISTS "authenticated_select_intel_intercepts" ON public.intel_intercepts;
DROP POLICY IF EXISTS "authenticated_insert_intel_intercepts" ON public.intel_intercepts;
DROP POLICY IF EXISTS "authenticated_update_intel_intercepts" ON public.intel_intercepts;

CREATE POLICY "authenticated_select_intel_intercepts" ON public.intel_intercepts
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_intel_intercepts" ON public.intel_intercepts
    FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_intel_intercepts" ON public.intel_intercepts
    FOR UPDATE TO authenticated USING (true);

-- ============================================================
-- SECTION 9: 权限授予
-- ============================================================

GRANT EXECUTE ON FUNCTION public.get_my_player_id TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_session_remaining_time TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_player_active_session_count TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_scene_listener_count TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_player_intercepted TO authenticated;

-- ============================================================
-- SECTION 10: 精力系统 RPC 函数
-- ============================================================

-- 管家身份校验 + 精力结算 & 扣减
CREATE OR REPLACE FUNCTION public.require_steward_and_consume_stamina(p_cost int)
RETURNS TABLE (steward_id uuid, game_id uuid, remaining_stamina int) AS $$
DECLARE
    v_player_id uuid;
    v_role text;
    v_game_id uuid;
    v_stamina int;
    v_max int;
    v_last timestamptz;
    v_now timestamptz;
    v_recovered int;
    v_interval_seconds int := 7200;
BEGIN
    SELECT id, role_class, current_game_id, stamina, stamina_max, stamina_refreshed_at
    INTO v_player_id, v_role, v_game_id, v_stamina, v_max, v_last
    FROM public.players
    WHERE id = public.get_my_player_id();

    IF v_player_id IS NULL THEN
        RAISE EXCEPTION '玩家不存在';
    END IF;

    IF v_role <> 'steward' THEN
        RAISE EXCEPTION '仅管家可用';
    END IF;

    v_now := now();
    IF v_last IS NULL THEN
        v_last := v_now;
    END IF;

    v_recovered := floor(extract(epoch FROM (v_now - v_last))::int / v_interval_seconds);
    v_stamina := LEAST(v_stamina + v_recovered, v_max);

    IF v_stamina < p_cost THEN
        RAISE EXCEPTION '精力不足';
    END IF;

    v_stamina := v_stamina - p_cost;

    UPDATE public.players
    SET stamina = v_stamina,
        stamina_refreshed_at = v_now,
        updated_at = v_now
    WHERE id = v_player_id;

    RETURN QUERY SELECT v_player_id, v_game_id, v_stamina;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 采办物资
CREATE OR REPLACE FUNCTION public.steward_procure_goods(
    p_item_template_key text,
    p_quantity int DEFAULT 1
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_ticket_id uuid;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(1);

    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        p_quantity := 1;
    END IF;

    INSERT INTO public.procurement_tickets (game_id, steward_uid, item_template_key, quantity)
    VALUES (v_game_id, v_steward_id, p_item_template_key, p_quantity)
    RETURNING id INTO v_ticket_id;

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_id,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'procurement', NULL,
        1,
        jsonb_build_object(
            'item_template_key', p_item_template_key,
            'quantity', p_quantity,
            'ticket_id', v_ticket_id
        ),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'ticket_id', v_ticket_id,
        'stamina', v_remaining
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 差使分派
CREATE OR REPLACE FUNCTION public.steward_assign_task(
    p_target_uid uuid,
    p_silver_reward int DEFAULT 10
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_new_silver int;
    v_new_stamina int;
    v_message_id uuid;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(1);

    IF p_target_uid IS NULL THEN
        RAISE EXCEPTION '目标玩家不能为空';
    END IF;

    UPDATE public.players
    SET silver = silver + COALESCE(p_silver_reward, 0),
        stamina = GREATEST(stamina - 2, 0),
        updated_at = now()
    WHERE id = p_target_uid
    RETURNING silver, stamina INTO v_new_silver, v_new_stamina;

    INSERT INTO public.messages (
        game_id, sender_uid, receiver_uid,
        content, message_type, stamina_cost, attachments
    ) VALUES (
        v_game_id,
        v_steward_id,
        p_target_uid,
        '你被派去办理一桩差事，略感辛劳，却得了些许赏银。',
        'batch_order',
        2,
        '[]'::jsonb
    )
    RETURNING id INTO v_message_id;

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_id,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'assignment', p_target_uid,
        1,
        jsonb_build_object(
            'silver_reward', COALESCE(p_silver_reward, 0),
            'message_id', v_message_id
        ),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'target_silver', v_new_silver,
        'target_stamina', v_new_stamina,
        'stamina', v_remaining,
        'message_id', v_message_id
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 预支批条
CREATE OR REPLACE FUNCTION public.steward_advance_credit(
    p_target_uid uuid,
    p_amount int DEFAULT 20,
    p_deficit_step int DEFAULT 5
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_new_silver int;
    v_new_deficit float;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(1);

    IF p_target_uid IS NULL THEN
        RAISE EXCEPTION '目标玩家不能为空';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION '预支金额必须为正数';
    END IF;

    UPDATE public.players
    SET silver = silver + p_amount,
        updated_at = now()
    WHERE id = p_target_uid
    RETURNING silver INTO v_new_silver;

    UPDATE public.games
    SET deficit_value = COALESCE(deficit_value, 0.0) + COALESCE(p_deficit_step, 5),
        updated_at = now()
    WHERE id = v_game_id
    RETURNING deficit_value INTO v_new_deficit;

    INSERT INTO public.deficit_log (
        game_id, operated_at, operated_by, delta_amount, new_deficit_percent
    ) VALUES (
        v_game_id, now(), v_steward_id, COALESCE(p_deficit_step, 5), v_new_deficit
    );

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_id,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'advance', p_target_uid,
        1,
        jsonb_build_object(
            'amount', p_amount,
            'deficit_step', COALESCE(p_deficit_step, 5)
        ),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'target_silver', v_new_silver,
        'deficit_value', v_new_deficit,
        'stamina', v_remaining
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 搜检功能
CREATE OR REPLACE FUNCTION public.steward_search_players(
    p_min_count int DEFAULT 5,
    p_max_count int DEFAULT 10,
    p_love_letter_rate float DEFAULT 0.3,
    p_account_fragment_rate float DEFAULT 0.25
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_n int;
    v_player record;
    v_results jsonb := '[]'::jsonb;
    v_found_love boolean;
    v_found_account boolean;
    v_any_loot boolean;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(2);

    IF p_min_count < 1 THEN p_min_count := 1; END IF;
    IF p_max_count < p_min_count THEN p_max_count := p_min_count; END IF;

    v_n := floor(random() * (p_max_count - p_min_count + 1))::int + p_min_count;

    FOR v_player IN
        SELECT id, character_name
        FROM public.players
        WHERE current_game_id = v_game_id
          AND id <> v_steward_id
        ORDER BY random()
        LIMIT v_n
    LOOP
        v_found_love := (random() < p_love_letter_rate);
        v_found_account := (random() < p_account_fragment_rate);
        v_any_loot := false;

        IF v_found_love THEN
            v_any_loot := true;
            INSERT INTO public.intel_fragments (
                game_id, owner_uid, source_uid, content,
                intel_type, scene, scene_key, value_level
            ) VALUES (
                v_game_id,
                v_steward_id,
                v_player.id,
                '在搜检' || COALESCE(v_player.character_name, '某人') || '时，意外发现一封藏好的情书。',
                'private_action',
                'bridge',
                'bridge',
                2
            );
        END IF;

        IF v_found_account THEN
            v_any_loot := true;
            INSERT INTO public.intel_fragments (
                game_id, owner_uid, source_uid, content,
                intel_type, scene, scene_key, value_level
            ) VALUES (
                v_game_id,
                v_steward_id,
                v_player.id,
                '从' || COALESCE(v_player.character_name, '某人') || '的物件中翻出几张来路不明的账目碎片。',
                'account_leak',
                'treasury_back',
                'treasury_back',
                3
            );
        END IF;

        v_results := v_results || jsonb_build_object(
            'player_id', v_player.id,
            'player_name', v_player.character_name,
            'found_love_letter', v_found_love,
            'found_account_fragment', v_found_account,
            'has_loot', v_any_loot
        );
    END LOOP;

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_id,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'search', NULL,
        2,
        jsonb_build_object('results', v_results),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'results', v_results,
        'stamina', v_remaining
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 平息流言
CREATE OR REPLACE FUNCTION public.steward_suppress_rumor(
    p_rumor_id uuid
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_exists boolean;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(2);

    IF p_rumor_id IS NULL THEN
        RAISE EXCEPTION 'rumor_id 不能为空';
    END IF;

    SELECT true
    INTO v_exists
    FROM public.rumors
    WHERE id = p_rumor_id
      AND game_id = v_game_id
    LIMIT 1;

    IF NOT COALESCE(v_exists, false) THEN
        RAISE EXCEPTION '目标流言不存在或不在当前局';
    END IF;

    UPDATE public.rumors
    SET is_suppressed = true,
        suppressed_by = v_steward_id,
        suppressed_at = now(),
        suppress_method = 'steward_order'
    WHERE id = p_rumor_id;

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_id,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'suppress_rumor', NULL,
        2,
        jsonb_build_object('rumor_id', p_rumor_id),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'stamina', v_remaining
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 封锁消息
CREATE OR REPLACE FUNCTION public.steward_block_intel(
    p_intel_id uuid
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_exists boolean;
    v_block_until timestamptz;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(3);

    IF p_intel_id IS NULL THEN
        RAISE EXCEPTION 'intel_id 不能为空';
    END IF;

    SELECT true
    INTO v_exists
    FROM public.intel_fragments
    WHERE id = p_intel_id
      AND game_id = v_game_id
    LIMIT 1;

    IF NOT COALESCE(v_exists, false) THEN
        RAISE EXCEPTION '目标情报不存在或不在当前局';
    END IF;

    v_block_until := now() + interval '12 hours';

    UPDATE public.intel_fragments
    SET is_blocked = true,
        blocked_until = v_block_until,
        blocked_by = v_steward_id
    WHERE id = p_intel_id;

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_id,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'block_intel', NULL,
        3,
        jsonb_build_object(
            'intel_id', p_intel_id,
            'blocked_until', v_block_until
        ),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'blocked_until', v_block_until,
        'stamina', v_remaining
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- SECTION 11: 银库操作 RPC 函数
-- ============================================================

-- 修改玩家属性
CREATE OR REPLACE FUNCTION public.modify_player_stats(
    p_id uuid,
    private_silver_delta int DEFAULT 0,
    silver_delta int DEFAULT 0,
    stamina_delta int DEFAULT 0,
    reputation_delta int DEFAULT 0,
    prestige_delta int DEFAULT 0,
    loyalty_delta int DEFAULT 0
)
RETURNS json AS $$
DECLARE
    v_player record;
    v_result json;
BEGIN
    SELECT * INTO v_player FROM public.players WHERE id = p_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Player not found');
    END IF;
    
    UPDATE public.players
    SET 
        private_silver = GREATEST(0, private_silver + COALESCE(private_silver_delta, 0)),
        silver = GREATEST(0, silver + COALESCE(silver_delta, 0)),
        stamina = GREATEST(0, LEAST(stamina_max, stamina + COALESCE(stamina_delta, 0))),
        reputation = GREATEST(0, LEAST(100, reputation + COALESCE(reputation_delta, 0))),
        prestige = GREATEST(0, LEAST(100, prestige + COALESCE(prestige_delta, 0))),
        loyalty = GREATEST(0, LEAST(100, loyalty + COALESCE(loyalty_delta, 0))),
        updated_at = now()
    WHERE id = p_id
    RETURNING * INTO v_player;
    
    v_result := json_build_object(
        'success', true,
        'player', json_build_object(
            'id', v_player.id,
            'private_silver', v_player.private_silver,
            'silver', v_player.silver,
            'stamina', v_player.stamina,
            'reputation', v_player.reputation,
            'prestige', v_player.prestige,
            'loyalty', v_player.loyalty
        )
    );
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- 扣除银库
CREATE OR REPLACE FUNCTION public.decrement_treasury(
    g_id uuid,
    amount int
)
RETURNS json AS $$
DECLARE
    v_treasury record;
    v_result json;
BEGIN
    SELECT * INTO v_treasury FROM public.treasury WHERE game_id = g_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Treasury not found');
    END IF;
    
    IF v_treasury.total_silver < amount THEN
        RETURN json_build_object('success', false, 'error', 'Insufficient funds in treasury');
    END IF;
    
    UPDATE public.treasury
    SET 
        total_silver = total_silver - amount,
        public_balance = public_balance - amount,
        real_balance = real_balance - amount,
        last_update = now()
    WHERE game_id = g_id
    RETURNING * INTO v_treasury;
    
    v_result := json_build_object(
        'success', true,
        'treasury', json_build_object(
            'game_id', v_treasury.game_id,
            'total_silver', v_treasury.total_silver,
            'public_balance', v_treasury.public_balance,
            'real_balance', v_treasury.real_balance
        )
    );
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- 发放月例（单人）
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
    v_treasury record;
    v_steward_acc record;
    v_withheld int;
    v_ratio float;
    v_timestamp timestamptz;
    v_public_entry jsonb;
    v_private_entry jsonb;
    v_count bigint;
    v_result json;
BEGIN
    SELECT * INTO v_treasury FROM public.treasury WHERE game_id = p_game_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Treasury not found');
    END IF;
    
    IF v_treasury.total_silver < p_actual_amount THEN
        RETURN json_build_object('success', false, 'error', 'Insufficient funds in treasury');
    END IF;
    
    v_withheld := p_standard_amount - p_actual_amount;
    v_ratio := CASE WHEN p_standard_amount > 0 THEN v_withheld::float / p_standard_amount::float ELSE 0 END;
    
    v_timestamp := now();
    
    -- 扣除银库
    UPDATE public.treasury
    SET 
        total_silver = total_silver - p_actual_amount,
        public_balance = public_balance - p_actual_amount,
        real_balance = real_balance - p_actual_amount,
        last_update = v_timestamp
    WHERE game_id = p_game_id;
    
    -- 更新目标玩家私产
    UPDATE public.players
    SET 
        private_silver = private_silver + p_actual_amount,
        updated_at = v_timestamp
    WHERE id = p_recipient_uid;
    
    -- 获取管家账户数据
    SELECT * INTO v_steward_acc 
    FROM public.steward_accounts 
    WHERE steward_uid = p_steward_uid AND game_id = p_game_id;
    
    IF NOT FOUND THEN
        INSERT INTO public.steward_accounts (game_id, steward_uid, public_ledger, private_ledger, private_assets)
        VALUES (p_game_id, p_steward_uid, '[]'::jsonb, '[]'::jsonb, 0)
        RETURNING * INTO v_steward_acc;
    END IF;
    
    -- 更新明账
    v_public_entry := jsonb_build_object(
        'type', 'allowance',
        'recipient_uid', p_recipient_uid,
        'recipient_name', p_recipient_name,
        'amount', p_actual_amount,
        'timestamp', v_timestamp
    );
    
    UPDATE public.steward_accounts
    SET 
        public_ledger = COALESCE(public_ledger, '[]'::jsonb) || v_public_entry,
        updated_at = v_timestamp
    WHERE steward_uid = p_steward_uid AND game_id = p_game_id;
    
    -- 更新暗账（如果有克扣）
    IF v_withheld > 0 THEN
        v_private_entry := jsonb_build_object(
            'type', 'embezzlement',
            'recipient_uid', p_recipient_uid,
            'recipient_name', p_recipient_name,
            'standard', p_standard_amount,
            'actual', p_actual_amount,
            'withheld', v_withheld,
            'timestamp', v_timestamp
        );
        
        UPDATE public.steward_accounts
        SET 
            private_ledger = COALESCE(private_ledger, '[]'::jsonb) || v_private_entry,
            private_assets = private_assets + v_withheld,
            updated_at = v_timestamp
        WHERE steward_uid = p_steward_uid AND game_id = p_game_id;
    END IF;
    
    -- 写入发放记录
    INSERT INTO public.allowance_records (
        game_id, issued_by, player_id, amount_public, amount_actual, withheld_amount, issued_at
    ) VALUES (
        p_game_id, p_steward_uid, p_recipient_uid, p_standard_amount, p_actual_amount, v_withheld, v_timestamp
    );
    
    -- 插入流水记录 (ledger_entries)
    INSERT INTO public.ledger_entries (
        game_id, treasury_id, actor_id, target_id, ledger_type, entry_type, amount, note, created_at
    ) VALUES (
        p_game_id, v_treasury.game_id, p_steward_uid, p_recipient_uid, 'public', 'allocation', 
        p_actual_amount, '发放月例：' || p_actual_amount || ' 两', v_timestamp
    );
    
    IF v_withheld > 0 THEN
        INSERT INTO public.ledger_entries (
            game_id, treasury_id, actor_id, target_id, ledger_type, entry_type, amount, note, created_at
        ) VALUES (
            p_game_id, v_treasury.game_id, p_steward_uid, p_recipient_uid, 'private', 'allocation', 
            v_withheld, '克扣月例：' || v_withheld || ' 两', v_timestamp
        );
    END IF;
    
    -- 触发告状风险检测 (本旬内克扣人数 >= 3)
    SELECT COUNT(*) INTO v_count
    FROM public.allowance_records
    WHERE issued_by = p_steward_uid
      AND game_id = p_game_id
      AND withheld_amount > 0
      AND created_at >= (now() - INTERVAL '10 days');
    
    IF v_count >= 3 THEN
        INSERT INTO public.intel_fragments (
            game_id, intel_type, content, source_uid, owner_uid, scene, scene_key
        ) VALUES (
            p_game_id, 'account_leak', 
            '有人偶然发现账房的月例支出似乎与各房领到的数额对不上。',
            p_steward_uid, p_steward_uid, 'treasury_back', 'treasury_back'
        );
    END IF;
    
    -- 碎片生成逻辑 (克扣比例)
    IF v_ratio > 0 THEN
        IF random() < (CASE WHEN v_ratio >= 0.25 THEN 0.8 WHEN v_ratio >= 0.10 THEN 0.4 ELSE 0.15 END) THEN
            INSERT INTO public.intel_fragments (
                game_id, intel_type, content, source_uid, owner_uid, scene, scene_key
            ) VALUES (
                p_game_id, 'account_leak',
                '听闻被克扣了 ' || v_withheld || ' 两月例。',
                p_steward_uid, p_recipient_uid, 'bridge', 'bridge'
            );
        END IF;
    END IF;
    
    RETURN json_build_object('success', true, 'withheld', v_withheld);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 批量发放月例
CREATE OR REPLACE FUNCTION public.bulk_distribute_allowance_rpc(
    p_steward_uid uuid,
    p_game_id uuid,
    p_distributions jsonb
)
RETURNS json AS $$
DECLARE
    v_treasury record;
    v_steward_acc record;
    v_dist jsonb;
    v_recipient_uid uuid;
    v_recipient_name text;
    v_actual_amount int;
    v_standard_amount int;
    v_withheld int;
    v_total_actual int := 0;
    v_total_withheld int := 0;
    v_timestamp timestamptz;
    v_public_entry jsonb;
    v_private_entry jsonb;
    v_public_ledger jsonb := '[]'::jsonb;
    v_private_ledger jsonb := '[]'::jsonb;
    v_private_assets_delta int := 0;
    v_withheld_count int := 0;
BEGIN
    SELECT * INTO v_treasury FROM public.treasury WHERE game_id = p_game_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Treasury not found');
    END IF;
    
    SELECT * INTO v_steward_acc 
    FROM public.steward_accounts 
    WHERE steward_uid = p_steward_uid AND game_id = p_game_id;
    
    IF NOT FOUND THEN
        INSERT INTO public.steward_accounts (game_id, steward_uid, public_ledger, private_ledger, private_assets)
        VALUES (p_game_id, p_steward_uid, '[]'::jsonb, '[]'::jsonb, 0)
        RETURNING * INTO v_steward_acc;
    END IF;
    
    v_timestamp := now();
    
    -- 计算总额并校验
    FOR v_dist IN SELECT * FROM jsonb_array_elements(p_distributions)
    LOOP
        v_actual_amount := (v_dist->>'actual_amount')::int;
        v_total_actual := v_total_actual + v_actual_amount;
    END LOOP;
    
    IF v_treasury.total_silver < v_total_actual THEN
        RETURN json_build_object('success', false, 'error', 'Insufficient funds in treasury');
    END IF;
    
    -- 处理每一个发放
    FOR v_dist IN SELECT * FROM jsonb_array_elements(p_distributions)
    LOOP
        v_recipient_uid := (v_dist->>'recipient_uid')::uuid;
        v_recipient_name := v_dist->>'recipient_name';
        v_actual_amount := (v_dist->>'actual_amount')::int;
        v_standard_amount := (v_dist->>'standard_amount')::int;
        v_withheld := v_standard_amount - v_actual_amount;
        
        v_total_withheld := v_total_withheld + v_withheld;
        
        IF v_withheld > 0 THEN
            v_withheld_count := v_withheld_count + 1;
        END IF;
        
        -- 更新玩家私产
        UPDATE public.players
        SET private_silver = private_silver + v_actual_amount, updated_at = v_timestamp
        WHERE id = v_recipient_uid;
        
        -- 准备账本条目
        v_public_entry := jsonb_build_object(
            'type', 'allowance',
            'recipient_uid', v_recipient_uid,
            'recipient_name', v_recipient_name,
            'amount', v_actual_amount,
            'timestamp', v_timestamp
        );
        v_public_ledger := v_public_ledger || v_public_entry;
        
        IF v_withheld > 0 THEN
            v_private_entry := jsonb_build_object(
                'type', 'embezzlement',
                'recipient_uid', v_recipient_uid,
                'recipient_name', v_recipient_name,
                'standard', v_standard_amount,
                'actual', v_actual_amount,
                'withheld', v_withheld,
                'timestamp', v_timestamp
            );
            v_private_ledger := v_private_ledger || v_private_entry;
            v_private_assets_delta := v_private_assets_delta + v_withheld;
        END IF;
        
        -- 插入发放记录
        INSERT INTO public.allowance_records (
            game_id, issued_by, player_id, amount_public, amount_actual, withheld_amount, issued_at
        ) VALUES (
            p_game_id, p_steward_uid, v_recipient_uid, v_standard_amount, v_actual_amount, v_withheld, v_timestamp
        );
        
        -- 插入流水记录 (ledger_entries)
        INSERT INTO public.ledger_entries (
            game_id, treasury_id, actor_id, target_id, ledger_type, entry_type, amount, note, created_at
        ) VALUES (
            p_game_id, v_treasury.game_id, p_steward_uid, v_recipient_uid, 'public', 'allocation', 
            v_actual_amount, '发放月例：' || v_actual_amount || ' 两', v_timestamp
        );
        
        IF v_withheld > 0 THEN
            INSERT INTO public.ledger_entries (
                game_id, treasury_id, actor_id, target_id, ledger_type, entry_type, amount, note, created_at
            ) VALUES (
                p_game_id, v_treasury.game_id, p_steward_uid, v_recipient_uid, 'private', 'allocation', 
                v_withheld, '克扣月例：' || v_withheld || ' 两', v_timestamp
            );
        END IF;
    END LOOP;
    
    -- 扣除银库
    UPDATE public.treasury
    SET 
        total_silver = total_silver - v_total_actual,
        public_balance = public_balance - v_total_actual,
        real_balance = real_balance - v_total_actual,
        last_update = v_timestamp
    WHERE game_id = p_game_id;
    
    -- 更新管家账户
    UPDATE public.steward_accounts
    SET 
        public_ledger = COALESCE(public_ledger, '[]'::jsonb) || v_public_ledger,
        private_ledger = COALESCE(private_ledger, '[]'::jsonb) || v_private_ledger,
        private_assets = private_assets + v_private_assets_delta,
        updated_at = v_timestamp
    WHERE steward_uid = p_steward_uid AND game_id = p_game_id;
    
    -- 风险检测：克扣人数 >= 3
    IF v_withheld_count >= 3 THEN
        INSERT INTO public.intel_fragments (
            game_id, intel_type, content, source_uid, owner_uid, scene, scene_key
        ) VALUES (
            p_game_id, 'account_leak',
            '本月发放月银，竟然有 ' || v_withheld_count || ' 位下人私下议论数额不对。',
            p_steward_uid, p_steward_uid, 'treasury_back', 'treasury_back'
        );
    END IF;
    
    RETURN json_build_object('success', true, 'total_distributed', v_total_actual, 'total_withheld', v_total_withheld);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 获取银库统计
CREATE OR REPLACE FUNCTION public.get_treasury_stats(p_game_id uuid)
RETURNS TABLE (
    sum_public bigint,
    sum_withheld bigint
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(amount_public), 0)::bigint,
        COALESCE(SUM(withheld_amount), 0)::bigint
    FROM public.allowance_records
    WHERE game_id = p_game_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- SECTION 11: 权限授予
-- ============================================================

-- 授予 anon 角色权限（本地开发环境需要）
GRANT ALL ON SCHEMA public TO anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon;

-- 授予 authenticated 角色权限（Supabase 云端环境需要）
GRANT EXECUTE ON FUNCTION public.get_my_player_id TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_session_remaining_time TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_player_active_session_count TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_scene_listener_count TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_player_intercepted TO authenticated;
GRANT EXECUTE ON FUNCTION public.modify_player_stats TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_treasury TO authenticated;
GRANT EXECUTE ON FUNCTION public.distribute_allowance_rpc TO authenticated;
GRANT EXECUTE ON FUNCTION public.bulk_distribute_allowance_rpc TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_treasury_stats TO authenticated;

-- ============================================================
-- 注释
-- ============================================================

COMMENT ON TABLE public.eavesdrop_sessions IS '挂机监听会话表，记录玩家挂机监听的会话信息';
COMMENT ON COLUMN public.eavesdrop_sessions.scene_key IS '场景键值（用于代码查询）';
COMMENT ON COLUMN public.eavesdrop_sessions.partner_uid IS '双人挂机搭档的 UID';
COMMENT ON COLUMN public.eavesdrop_sessions.is_duo IS '是否为双人挂机';
COMMENT ON COLUMN public.eavesdrop_sessions.success_rate_mod IS '成功率修正系数 (0.0-1.0)';
COMMENT ON COLUMN public.eavesdrop_sessions.result_count IS '已生成的情报数量';

COMMENT ON TABLE public.intel_fragments IS '情报碎片表，存储玩家通过挂机获得的情报';
COMMENT ON COLUMN public.intel_fragments.scene IS '情报来源场景（scene_location 类型）';
COMMENT ON COLUMN public.intel_fragments.scene_key IS '情报来源场景键值（text 类型）';
COMMENT ON COLUMN public.intel_fragments.session_id IS '关联的挂机会话 ID';
COMMENT ON COLUMN public.intel_fragments.status IS '情报状态：unread, read, used';
COMMENT ON COLUMN public.intel_fragments.is_used IS '是否已使用（发布流言）';
COMMENT ON COLUMN public.intel_fragments.is_sold IS '是否已出售';

COMMENT ON TABLE public.intel_intercepts IS '情报拦截表，记录管家对玩家的情报拦截';
COMMENT ON COLUMN public.intel_intercepts.interceptor_uid IS '执行拦截的管家 UID';
COMMENT ON COLUMN public.intel_intercepts.target_uid IS '被拦截的目标玩家 UID';
