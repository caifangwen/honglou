-- ################################################################################
-- ## 《红楼回忆志》本地数据库完整初始化脚本
-- ## 包含：完整表结构 + RLS 权限 + 修复后的权限策略
-- ## 使用方法：在 Supabase SQL Editor 或本地 PostgreSQL 执行
-- ################################################################################

-- ==================== 第一部分：基础表和结构 ====================

-- 启用扩展
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

-- 创建枚举类型
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'steward_route') THEN
        CREATE TYPE steward_route AS ENUM ('virtuous', 'schemer', 'undecided');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'action_type') THEN
        CREATE TYPE action_type AS ENUM ('procurement', 'assignment', 'search', 'advance', 'suppress_rumor', 'block_intel');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'approval_status') THEN
        CREATE TYPE approval_status AS ENUM ('pending', 'executed', 'cancelled');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'audit_status') THEN
        CREATE TYPE audit_status AS ENUM ('filed', 'investigating', 'concluded');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'audit_verdict') THEN
        CREATE TYPE audit_verdict AS ENUM ('acquitted', 'demoted', 'catastrophe');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'intel_type') THEN
        CREATE TYPE intel_type AS ENUM ('account_leak', 'private_action', 'gift_record', 'visitor_info', 'elder_favor');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'scene_location') THEN
        CREATE TYPE scene_location AS ENUM ('yi_hong_yuan', 'treasury_back', 'bridge', 'gate', 'elder_room');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'session_status') THEN
        CREATE TYPE session_status AS ENUM ('active', 'completed', 'interrupted');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_status') THEN
        CREATE TYPE message_status AS ENUM ('pending', 'delivered', 'intercepted', 'tampered');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'trade_status') THEN
        CREATE TYPE trade_status AS ENUM ('pending', 'completed', 'cancelled');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'maid_relation_type') THEN
        CREATE TYPE maid_relation_type AS ENUM ('dui_shi', 'si_yue');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'maid_relation_status') THEN
        CREATE TYPE maid_relation_status AS ENUM ('pending', 'active', 'betrayed', 'dissolved');
    END IF;
END $$;

-- ==================== 第二部分：核心表 ====================

-- 1. games 表
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

-- 2. players 表
CREATE TABLE IF NOT EXISTS public.players (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_uid uuid UNIQUE NOT NULL,
    username text UNIQUE,
    display_name text NOT NULL,
    character_name text,
    role_class text NOT NULL CHECK (role_class IN ('steward', 'master', 'servant', 'elder', 'guest')),
    current_game_id uuid,
    stamina int DEFAULT 6,
    stamina_max int DEFAULT 6,
    stamina_refreshed_at timestamptz DEFAULT now(),
    qi_points int DEFAULT 100,
    silver int DEFAULT 0,
    private_silver int DEFAULT 0,
    face_value int DEFAULT 50,
    prestige int DEFAULT 10,
    loyalty int DEFAULT 50,
    reputation int DEFAULT 50,
    karma_score int DEFAULT 0,
    is_disgraced boolean DEFAULT false,
    betrayal_count int DEFAULT 0,
    permissions jsonb DEFAULT '[]',
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- 3. treasury 表
CREATE TABLE IF NOT EXISTS public.treasury (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL UNIQUE,
    total_silver int DEFAULT 10000,
    daily_budget int DEFAULT 1000,
    public_balance numeric(10,2) DEFAULT 10000,
    real_balance numeric(10,2) DEFAULT 10000,
    prosperity_level int DEFAULT 1 CHECK (prosperity_level BETWEEN 1 AND 10),
    deficit_rate float DEFAULT 0.0 CHECK (deficit_rate BETWEEN 0.0 AND 1.0),
    last_allocation_day int DEFAULT 0,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- 4. ledger_entries 表
CREATE TABLE IF NOT EXISTS public.ledger_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL,
    treasury_id uuid NOT NULL,
    ledger_type text NOT NULL CHECK (ledger_type IN ('public', 'private')),
    entry_type text NOT NULL,
    amount numeric(10,2) NOT NULL,
    actor_id uuid,
    target_id uuid,
    note text,
    created_at timestamptz DEFAULT now()
);

-- 5. allowance_records 表
CREATE TABLE IF NOT EXISTS public.allowance_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL,
    player_id uuid,
    issued_by uuid,
    amount_public int NOT NULL,
    amount_actual int NOT NULL,
    withheld_amount int DEFAULT 0,
    is_public boolean DEFAULT true,
    issued_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now()
);

-- 6. deficit_log 表
CREATE TABLE IF NOT EXISTS public.deficit_log (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid,
    operated_at timestamptz DEFAULT now(),
    operated_by uuid,
    delta_amount int NOT NULL,
    new_deficit_percent float NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- 7. rumors 表
CREATE TABLE IF NOT EXISTS public.rumors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL,
    publisher_uid UUID NOT NULL,
    target_uid UUID NOT NULL,
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
    suppressed_by UUID,
    suppressed_at TIMESTAMPTZ,
    suppress_method TEXT,
    publisher_exposed BOOLEAN DEFAULT FALSE,
    exposure_method TEXT,
    penalty_applied BOOLEAN DEFAULT FALSE,
    damage_multiplier NUMERIC(3,1) DEFAULT 1.0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. rumor_events 表
CREATE TABLE IF NOT EXISTS public.rumor_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rumor_id UUID NOT NULL,
    actor_uid UUID NOT NULL,
    event_type TEXT NOT NULL,
    event_data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. messages 表
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL,
    sender_uid UUID,
    receiver_uid UUID,
    content TEXT DEFAULT '',
    original_content TEXT,
    delivered_content TEXT,
    message_type TEXT NOT NULL DEFAULT 'private',
    is_tampered BOOLEAN DEFAULT FALSE,
    is_intercepted BOOLEAN DEFAULT FALSE,
    is_read BOOLEAN DEFAULT FALSE,
    carrier_uid UUID,
    small_fee INTEGER DEFAULT 0,
    stamina_cost INT DEFAULT 0,
    attachments JSONB DEFAULT '[]',
    stage INT DEFAULT 0,
    expires_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    delivered_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. intel_fragments 表
CREATE TABLE IF NOT EXISTS public.intel_fragments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL,
    owner_uid UUID NOT NULL,
    source_uid UUID,
    content TEXT NOT NULL,
    intel_type intel_type NOT NULL,
    scene scene_location NOT NULL,
    value_level INTEGER DEFAULT 1 CHECK (value_level BETWEEN 1 AND 5),
    is_used BOOLEAN DEFAULT FALSE,
    is_sold BOOLEAN DEFAULT FALSE,
    obtained_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '48 hours'),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. steward_accounts 表
CREATE TABLE IF NOT EXISTS public.steward_accounts (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL,
    steward_uid uuid NOT NULL,
    public_ledger jsonb DEFAULT '[]',
    private_ledger jsonb DEFAULT '[]',
    private_assets int DEFAULT 0,
    prestige int DEFAULT 50,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(game_id, steward_uid)
);

-- ==================== 第三部分：RLS 权限策略（关键修复）====================

-- 启用 RLS
ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treasury ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.allowance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deficit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rumors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rumor_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intel_fragments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.steward_accounts ENABLE ROW LEVEL SECURITY;

-- 删除旧策略（如果存在）
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

-- ==================== 第四部分：创建新策略 ====================

-- 1. Games 表
CREATE POLICY "authenticated_select_games" ON public.games
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_games" ON public.games
    FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_games" ON public.games
    FOR UPDATE TO authenticated USING (true);

-- 2. Players 表
CREATE POLICY "authenticated_select_players" ON public.players
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_players" ON public.players
    FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_players" ON public.players
    FOR UPDATE TO authenticated USING (auth.uid() = auth_uid);

-- 3. Rumors 表（核心修复）
CREATE POLICY "authenticated_select_rumors" ON public.rumors
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_rumors" ON public.rumors
    FOR INSERT TO authenticated 
    WITH CHECK (true);
CREATE POLICY "authenticated_update_rumors" ON public.rumors
    FOR UPDATE TO authenticated USING (true);

-- 4. Rumor events 表
CREATE POLICY "authenticated_select_rumor_events" ON public.rumor_events
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_rumor_events" ON public.rumor_events
    FOR INSERT TO authenticated WITH CHECK (true);

-- 5. Intel fragments 表
CREATE POLICY "authenticated_select_intel_fragments" ON public.intel_fragments
    FOR SELECT TO authenticated 
    USING (true);
CREATE POLICY "authenticated_insert_intel_fragments" ON public.intel_fragments
    FOR INSERT TO authenticated 
    WITH CHECK (true);
CREATE POLICY "authenticated_update_intel_fragments" ON public.intel_fragments
    FOR UPDATE TO authenticated 
    USING (true);

-- 6. Messages 表
CREATE POLICY "authenticated_select_messages" ON public.messages
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_messages" ON public.messages
    FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_messages" ON public.messages
    FOR UPDATE TO authenticated USING (true);

-- 7. Steward accounts 表
CREATE POLICY "authenticated_select_steward_accounts" ON public.steward_accounts
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_steward_accounts" ON public.steward_accounts
    FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_steward_accounts" ON public.steward_accounts
    FOR UPDATE TO authenticated USING (true);

-- 8. Treasury 表
CREATE POLICY "authenticated_select_treasury" ON public.treasury
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_treasury" ON public.treasury
    FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_treasury" ON public.treasury
    FOR UPDATE TO authenticated USING (true);

-- 9. Allowance records 表
CREATE POLICY "authenticated_select_allowance_records" ON public.allowance_records
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_allowance_records" ON public.allowance_records
    FOR INSERT TO authenticated WITH CHECK (true);

-- 10. Ledger entries 表
CREATE POLICY "authenticated_select_ledger_entries" ON public.ledger_entries
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_ledger_entries" ON public.ledger_entries
    FOR INSERT TO authenticated WITH CHECK (true);

-- 11. Deficit log 表
CREATE POLICY "authenticated_select_deficit_log" ON public.deficit_log
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_deficit_log" ON public.deficit_log
    FOR INSERT TO authenticated WITH CHECK (true);

-- ==================== 第五部分：辅助函数 ====================

-- 获取当前玩家 ID
CREATE OR REPLACE FUNCTION public.get_my_player_id()
RETURNS UUID AS $$
    SELECT id FROM public.players WHERE auth_uid = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER;

-- ==================== 第六部分：RPC 函数（月银发放）====================

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
    SELECT id, total_silver
    INTO v_treasury_id, v_total_silver
    FROM public.treasury
    WHERE game_id = p_game_id;

    IF v_treasury_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', '未找到银库数据');
    END IF;

    IF v_total_silver < p_actual_amount THEN
        RETURN json_build_object('success', false, 'error', '银库余额不足');
    END IF;

    v_withheld := p_standard_amount - p_actual_amount;

    UPDATE public.treasury
    SET total_silver = total_silver - p_actual_amount,
        updated_at = now()
    WHERE id = v_treasury_id;

    UPDATE public.players
    SET private_silver = private_silver + p_actual_amount,
        updated_at = now()
    WHERE id = p_recipient_uid;

    v_public_entry := json_build_object(
        'type', 'allowance',
        'recipient_uid', p_recipient_uid,
        'recipient_name', p_recipient_name,
        'amount', p_actual_amount,
        'timestamp', now()
    );

    INSERT INTO public.steward_accounts (game_id, steward_uid, public_ledger, updated_at)
    VALUES (p_game_id, p_steward_uid, jsonb_build_array(v_public_entry), now())
    ON CONFLICT (game_id, steward_uid) DO UPDATE
    SET public_ledger = public.steward_accounts.public_ledger || v_public_entry,
        updated_at = now();

    INSERT INTO public.ledger_entries (
        game_id, treasury_id, ledger_type, entry_type, amount, actor_id, target_id, note
    )
    VALUES (
        p_game_id, v_treasury_id, 'public', 'allocation', p_actual_amount,
        p_steward_uid, p_recipient_uid, '发放月例：' || p_actual_amount || ' 两'
    );

    IF v_withheld > 0 THEN
        v_private_entry := json_build_object(
            'type', 'embezzlement',
            'recipient_uid', p_recipient_uid,
            'recipient_name', p_recipient_name,
            'standard', p_standard_amount,
            'actual', p_actual_amount,
            'withheld', v_withheld,
            'timestamp', now()
        );

        INSERT INTO public.steward_accounts (game_id, steward_uid, private_assets, private_ledger, updated_at)
        VALUES (p_game_id, p_steward_uid, v_withheld, jsonb_build_array(v_private_entry), now())
        ON CONFLICT (game_id, steward_uid) DO UPDATE
        SET private_assets = public.steward_accounts.private_assets + v_withheld,
            private_ledger = public.steward_accounts.private_ledger || v_private_entry,
            updated_at = now();

        INSERT INTO public.ledger_entries (
            game_id, treasury_id, ledger_type, entry_type, amount, actor_id, target_id, note
        )
        VALUES (
            p_game_id, v_treasury_id, 'private', 'allocation', v_withheld,
            p_steward_uid, p_recipient_uid, '克扣月例：' || v_withheld || ' 两'
        );
    END IF;

    SELECT COUNT(*)
    INTO v_withheld_count
    FROM public.allowance_records
    WHERE game_id = p_game_id AND withheld_amount > 0;

    IF v_withheld_count >= 3 THEN
        INSERT INTO public.intel_fragments (
            game_id, intel_type, content, source_uid, owner_uid, scene
        )
        VALUES (
            p_game_id, 'account_leak',
            '府中已有三名下人因月例被扣私下议论，管家账目恐有疏漏。',
            p_steward_uid, p_steward_uid, 'treasury_back'
        );
    END IF;

    RETURN json_build_object('success', true);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 授予 RPC 执行权限
GRANT EXECUTE ON FUNCTION public.distribute_allowance_rpc(uuid, uuid, text, int, int, uuid) TO authenticated;
