-- ============================================================
-- 《红楼回忆志》完整数据库架构文件
-- 版本：2026-03-18
-- 使用方法：在 Supabase SQL Editor 或本地 PostgreSQL 中执行
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
            'account_leak', 'private_action', 'gift_record', 'visitor_info', 'elder_favor', 'dui_shi'
        );
    END IF;

    -- 场景地点
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'scene_location') THEN
        CREATE TYPE scene_location AS ENUM (
            'yi_hong_yuan', 'treasury_back', 'bridge', 'gate', 'elder_room', 'remote_rockery', 'empty_room'
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
    message_type text NOT NULL DEFAULT 'private' CHECK (message_type IN ('private', 'rumor', 'batch_order', 'system', 'petition', 'accusation')),
    content text NOT NULL,
    attachments jsonb DEFAULT '[]'::jsonb,
    stamina_cost int NOT NULL DEFAULT 1,
    is_read boolean DEFAULT FALSE,
    is_tampered boolean DEFAULT false,
    original_content text,
    is_intercepted boolean DEFAULT false,
    stage int NOT NULL DEFAULT 0,
    expires_at timestamptz,
    status message_status DEFAULT 'pending',
    created_at timestamptz DEFAULT now(),
    read_at timestamptz
);

-- 添加索引
CREATE INDEX IF NOT EXISTS idx_messages_game_receiver ON public.messages(game_id, receiver_uid);
CREATE INDEX IF NOT EXISTS idx_messages_type ON public.messages(message_type);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON public.messages(sender_uid);

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
    is_blocked boolean DEFAULT false,
    blocked_until timestamptz,
    blocked_by uuid REFERENCES public.players(id),
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
    formed_at timestamptz,
    shared_intel_ids uuid[] DEFAULT '{}',
    betrayer_uid uuid REFERENCES public.players(id),
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

-- procurement_tickets 索引
CREATE INDEX IF NOT EXISTS idx_procurement_tickets_game ON public.procurement_tickets(game_id);
CREATE INDEX IF NOT EXISTS idx_procurement_tickets_steward ON public.procurement_tickets(steward_uid);

-- ============================================================
-- SECTION 7: 辅助函数
-- ============================================================

-- 获取当前玩家 ID（本地/云端兼容）
CREATE OR REPLACE FUNCTION public.get_my_player_id()
RETURNS uuid AS $$
DECLARE
    v_player_id uuid;
BEGIN
    -- 尝试从 auth.uid() 获取
    BEGIN
        SELECT id INTO v_player_id FROM public.players
        WHERE auth_uid = auth.uid()
        LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        -- 本地环境：返回第一个管家玩家
        SELECT id INTO v_player_id FROM public.players
        WHERE role_class = 'steward'
        ORDER BY updated_at DESC
        LIMIT 1;
    END;
    
    RETURN v_player_id;
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
-- SECTION 8: 精力系统 RPC 函数
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
    v_current_user_id uuid;
BEGIN
    -- 本地兼容：尝试从 auth.uid() 或 current_setting 获取用户 ID
    BEGIN
        v_current_user_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        -- 本地环境：使用第一个管家玩家作为测试
        SELECT id INTO v_current_user_id FROM public.players WHERE role_class = 'steward' LIMIT 1;
    END;

    -- 基于当前用户获取玩家
    SELECT id, role_class, current_game_id, stamina, stamina_max, stamina_refreshed_at
    INTO v_player_id, v_role, v_game_id, v_stamina, v_max, v_last
    FROM public.players
    WHERE id = v_current_user_id;

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
    p_silver_reward int DEFAULT 10,
    p_task_type text DEFAULT 'errand'
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_new_silver int;
    v_new_stamina int;
    v_message_id uuid;
    v_stamina_drain int;
    v_message_content text;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(1);

    IF p_target_uid IS NULL THEN
        RAISE EXCEPTION '目标玩家不能为空';
    END IF;

    -- 根据差事类型设置精力消耗和消息内容
    v_stamina_drain := 2; -- 默认
    v_message_content := '你被派去办理一桩差事，略感辛劳，却得了些许赏银。';
    
    IF p_task_type = 'errand' THEN
        v_stamina_drain := 2;
        v_message_content := '你被派去跑腿办事，来回奔波，幸得赏银鼓励。';
    ELSIF p_task_type = 'guard' THEN
        v_stamina_drain := 1;
        v_message_content := '你被派去看守门户，职责重大，需谨慎行事。';
    ELSIF p_task_type = 'purchase' THEN
        v_stamina_drain := 3;
        v_message_content := '你被派去采办物品，货比三家，颇费心力。';
    ELSIF p_task_type = 'message' THEN
        v_stamina_drain := 2;
        v_message_content := '你被派去传话递信，言辞需谨慎，不可有误。';
    ELSIF p_task_type = 'clean' THEN
        v_stamina_drain := 2;
        v_message_content := '你被派去打扫庭院，虽为琐事，亦不可懈怠。';
    ELSIF p_task_type = 'special' THEN
        v_stamina_drain := 4;
        v_message_content := '你被派去办理特殊差事，责任重大，需全力以赴。';
    END IF;

    -- 目标玩家精力扣除，银两增加
    UPDATE public.players
    SET silver = silver + COALESCE(p_silver_reward, 0),
        stamina = GREATEST(stamina - v_stamina_drain, 0),
        updated_at = now()
    WHERE id = p_target_uid
    RETURNING silver, stamina INTO v_new_silver, v_new_stamina;

    -- 写一条"差事"消息
    INSERT INTO public.messages (
        game_id, sender_uid, receiver_uid,
        content, message_type, stamina_cost, attachments
    ) VALUES (
        v_game_id,
        v_steward_id,
        p_target_uid,
        v_message_content,
        'batch_order',
        v_stamina_drain,
        jsonb_build_object('task_type', p_task_type, 'silver_reward', p_silver_reward)
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
            'message_id', v_message_id,
            'task_type', p_task_type,
            'stamina_drain', v_stamina_drain
        ),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'target_silver', v_new_silver,
        'target_stamina', v_new_stamina,
        'stamina', v_remaining,
        'message_id', v_message_id,
        'task_type', p_task_type,
        'stamina_drain', v_stamina_drain
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

    -- 发放银两
    UPDATE public.players
    SET silver = silver + p_amount,
        updated_at = now()
    WHERE id = p_target_uid
    RETURNING silver INTO v_new_silver;

    -- 亏空 +5
    UPDATE public.games
    SET deficit_value = COALESCE(deficit_value, 0.0) + COALESCE(p_deficit_step, 5),
        updated_at = now()
    WHERE id = v_game_id
    RETURNING deficit_value INTO v_new_deficit;

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
-- SECTION 9: RLS 策略
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
-- SECTION 10: 权限授予
-- ============================================================

GRANT EXECUTE ON FUNCTION public.get_my_player_id TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_session_remaining_time TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_player_active_session_count TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_scene_listener_count TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_player_intercepted TO authenticated;

GRANT EXECUTE ON FUNCTION public.require_steward_and_consume_stamina TO authenticated;
GRANT EXECUTE ON FUNCTION public.steward_procure_goods TO authenticated;
GRANT EXECUTE ON FUNCTION public.steward_assign_task TO authenticated;
GRANT EXECUTE ON FUNCTION public.steward_advance_credit TO authenticated;
GRANT EXECUTE ON FUNCTION public.steward_search_players TO authenticated;
GRANT EXECUTE ON FUNCTION public.steward_suppress_rumor TO authenticated;
GRANT EXECUTE ON FUNCTION public.steward_block_intel TO authenticated;

-- ============================================================
-- SECTION 11: 表注释
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
COMMENT ON COLUMN public.intel_fragments.is_blocked IS '是否被管家封锁';
COMMENT ON COLUMN public.intel_fragments.blocked_until IS '封锁截止时间';
COMMENT ON COLUMN public.intel_fragments.blocked_by IS '执行封锁的管家 UID';

COMMENT ON TABLE public.intel_intercepts IS '情报拦截表，记录管家对玩家的情报拦截';
COMMENT ON COLUMN public.intel_intercepts.interceptor_uid IS '执行拦截的管家 UID';
COMMENT ON COLUMN public.intel_intercepts.target_uid IS '被拦截的目标玩家 UID';

COMMENT ON TABLE public.messages IS '消息表，支持私信、流言、批条等多种类型';
COMMENT ON COLUMN public.messages.message_type IS '消息类型：private, rumor, batch_order, system, petition, accusation';
COMMENT ON COLUMN public.messages.attachments IS '附件列表，如情报碎片';
COMMENT ON COLUMN public.messages.stamina_cost IS '精力消耗';
COMMENT ON COLUMN public.messages.is_tampered IS '是否被丫鬟篡改';
COMMENT ON COLUMN public.messages.original_content IS '原始内容（被篡改前）';
COMMENT ON COLUMN public.messages.is_intercepted IS '是否被丫鬟截留';
COMMENT ON COLUMN public.messages.stage IS '流言发酵阶段：0=初期，1=发酵中，2=已成实质';
COMMENT ON COLUMN public.messages.expires_at IS '过期时间（流言专用）';

COMMENT ON TABLE public.procurement_tickets IS '采办物资票据表';
COMMENT ON COLUMN public.procurement_tickets.item_template_key IS '物品模板键';
COMMENT ON COLUMN public.procurement_tickets.quantity IS '数量';
COMMENT ON COLUMN public.procurement_tickets.status IS '状态：pending, used, cancelled';

COMMENT ON TABLE public.action_approvals IS '行动批条表，记录管家执行的行动';
COMMENT ON COLUMN public.action_approvals.action_type IS '行动类型';
COMMENT ON COLUMN public.action_approvals.stamina_cost IS '精力消耗';
COMMENT ON COLUMN public.action_approvals.params IS '行动参数（JSONB）';
