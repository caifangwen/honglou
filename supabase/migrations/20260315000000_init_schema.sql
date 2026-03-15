-- ============================================================
-- 《红楼回忆志》数据库架构文件
-- 版本：2026-03-15
-- 使用方法：在 Supabase SQL Editor 中执行
-- ============================================================

-- ============================================================
-- SECTION 1: 基础设置与扩展
-- ============================================================

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
    qi_points int DEFAULT 100,
    silver int DEFAULT 0,
    private_silver int DEFAULT 0,
    reputation int DEFAULT 50,
    face_value int DEFAULT 50,
    prestige int DEFAULT 50,
    loyalty int DEFAULT 50,
    last_stamina_refresh timestamptz DEFAULT now(),
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
    actor_id uuid NOT NULL REFERENCES public.players(id),
    target_id uuid REFERENCES public.players(id),
    action_type action_type NOT NULL,
    amount int DEFAULT 0,
    approval_status approval_status DEFAULT 'pending',
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
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
-- SECTION 7: 辅助函数
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
