-- ============================================================
-- 《红楼回忆志》数据库 Schema v2.0 (重构版)
-- 目标：PostgreSQL 15 (Supabase)
-- 设计原则：3NF + 性能优化 + 可维护性
-- ============================================================

-- 扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- ============================================================
-- 通用触发器函数
-- ============================================================

-- 自动更新时间
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    BEGIN
        NEW.updated_by = current_setting('app.current_player_id', true)::uuid;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 软删除检查
CREATE OR REPLACE FUNCTION public.check_not_deleted()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION '无法更新已删除的记录';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 游戏局表 (games)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.games (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'crisis', 'purge', 'ended')),
    start_timestamp bigint NOT NULL,
    end_timestamp bigint,
    speed_multiplier float NOT NULL DEFAULT 1.0 CHECK (speed_multiplier > 0),
    deficit_value float NOT NULL DEFAULT 0.0 CHECK (deficit_value BETWEEN 0 AND 100),
    conflict_value float NOT NULL DEFAULT 0.0 CHECK (conflict_value BETWEEN 0 AND 100),
    current_day int NOT NULL DEFAULT 1 CHECK (current_day > 0),
    started_at timestamptz DEFAULT now(),
    ended_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    created_by uuid,
    updated_by uuid
);

COMMENT ON TABLE public.games IS '游戏局表，记录每局游戏的运行状态';
COMMENT ON COLUMN public.games.deficit_value IS '家族亏空值 (0-100%)';
COMMENT ON COLUMN public.games.conflict_value IS '家族内耗值 (0-100%)';

CREATE INDEX IF NOT EXISTS idx_games_status ON public.games(status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_games_created ON public.games(created_at DESC);

-- ============================================================
-- 玩家基础信息表 (players)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.players (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_uid uuid UNIQUE NOT NULL,
    username text UNIQUE,
    display_name text NOT NULL,
    character_name text,
    current_game_id uuid NOT NULL REFERENCES public.games(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    
    CONSTRAINT players_unique_game_auth UNIQUE (current_game_id, auth_uid)
);

COMMENT ON TABLE public.players IS '玩家基础信息表（仅存储身份标识）';

CREATE INDEX IF NOT EXISTS idx_players_auth_game ON public.players(auth_uid, current_game_id) 
    INCLUDE (display_name, character_name) WHERE deleted_at IS NULL;

-- ============================================================
-- 玩家角色属性表 (player_role_stats)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.player_role_stats (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id uuid NOT NULL UNIQUE REFERENCES public.players(id) ON DELETE CASCADE,
    role_class text NOT NULL CHECK (role_class IN ('steward', 'master', 'servant', 'elder', 'guest')),
    
    silver int NOT NULL DEFAULT 0 CHECK (silver >= 0),
    reputation int NOT NULL DEFAULT 50 CHECK (reputation BETWEEN 0 AND 100),
    face_value int NOT NULL DEFAULT 50 CHECK (face_value BETWEEN 0 AND 100),
    qi_points int NOT NULL DEFAULT 100 CHECK (qi_points >= 0),
    
    private_silver int DEFAULT 0 CHECK (private_silver >= 0),
    prestige int DEFAULT 50 CHECK (prestige BETWEEN 0 AND 100),
    route text DEFAULT 'undecided' CHECK (route IN ('virtuous', 'schemer', 'undecided')),
    
    loyalty int DEFAULT 50 CHECK (loyalty BETWEEN 0 AND 100),
    betrayal_count int NOT NULL DEFAULT 0 CHECK (betrayal_count >= 0),
    is_disgraced boolean NOT NULL DEFAULT false,
    
    stamina int NOT NULL DEFAULT 6 CHECK (stamina >= 0),
    stamina_max int NOT NULL DEFAULT 6 CHECK (stamina_max > 0),
    stamina_refreshed_at timestamptz DEFAULT now(),
    
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.player_role_stats IS '玩家角色属性表（按角色类型分离属性）';

CREATE INDEX IF NOT EXISTS idx_player_stats_role ON public.player_role_stats(role_class, player_id);

-- ============================================================
-- 银库表 (treasury)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.treasury (
    game_id uuid PRIMARY KEY REFERENCES public.games(id) ON DELETE CASCADE,
    total_silver int NOT NULL DEFAULT 50000 CHECK (total_silver >= 0),
    daily_budget int NOT NULL DEFAULT 2000 CHECK (daily_budget > 0),
    deficit_value float NOT NULL DEFAULT 0.0 CHECK (deficit_value BETWEEN 0 AND 100),
    last_update timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.treasury IS '银库表（精简版）';

-- ============================================================
-- 银库派生数据视图
-- ============================================================

CREATE OR REPLACE VIEW public.treasury_derived AS
SELECT 
    t.game_id,
    t.total_silver,
    t.daily_budget,
    t.deficit_value,
    t.last_update,
    t.total_silver AS public_balance,
    (t.total_silver * (1 - t.deficit_value / 100.0))::int AS real_balance,
    CASE 
        WHEN t.total_silver >= 100000 THEN 10
        WHEN t.total_silver >= 80000 THEN 9
        WHEN t.total_silver >= 60000 THEN 8
        WHEN t.total_silver >= 40000 THEN 7
        WHEN t.total_silver >= 20000 THEN 6
        WHEN t.total_silver >= 10000 THEN 5
        WHEN t.total_silver >= 5000 THEN 4
        WHEN t.total_silver >= 1000 THEN 3
        WHEN t.total_silver >= 500 THEN 2
        ELSE 1
    END AS prosperity_level
FROM public.treasury t;

-- ============================================================
-- 管家账本表 (steward_accounts)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.steward_accounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    steward_uid uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    prestige int NOT NULL DEFAULT 50 CHECK (prestige BETWEEN 0 AND 100),
    route text NOT NULL DEFAULT 'undecided' CHECK (route IN ('virtuous', 'schemer', 'undecided')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    
    CONSTRAINT steward_accounts_unique UNIQUE (game_id, steward_uid)
);

COMMENT ON TABLE public.steward_accounts IS '管家账本主表';

CREATE INDEX IF NOT EXISTS idx_steward_accounts_game_uid ON public.steward_accounts(game_id, steward_uid) 
    WHERE deleted_at IS NULL;

-- ============================================================
-- 账本条目表 (ledger_entries)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.ledger_entries (
    id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    steward_account_id uuid NOT NULL REFERENCES public.steward_accounts(id) ON DELETE CASCADE,
    ledger_type text NOT NULL CHECK (ledger_type IN ('public', 'private')),
    entry_type text NOT NULL CHECK (entry_type IN ('allowance', 'procurement', 'advance', 'embezzlement', 'other')),
    amount int NOT NULL DEFAULT 0,
    recipient_id uuid REFERENCES public.players(id),
    recipient_name text NOT NULL,
    note text,
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

COMMENT ON TABLE public.ledger_entries IS '账本条目明细表';

CREATE INDEX IF NOT EXISTS idx_ledger_entries_account ON public.ledger_entries(steward_account_id, ledger_type, created_at DESC)
    WHERE deleted_at IS NULL;

-- ============================================================
-- 消息表 (messages)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    sender_uid uuid NOT NULL REFERENCES public.players(id),
    receiver_uid uuid NOT NULL REFERENCES public.players(id),
    message_type text NOT NULL CHECK (message_type IN ('private', 'batch_order', 'system', 'petition', 'accusation')),
    content text NOT NULL,
    attachments jsonb DEFAULT '[]'::jsonb,
    stamina_cost int NOT NULL DEFAULT 0,
    is_read boolean NOT NULL DEFAULT false,
    is_intercepted boolean NOT NULL DEFAULT false,
    read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

COMMENT ON TABLE public.messages IS '消息表';

CREATE INDEX IF NOT EXISTS idx_messages_game_receiver ON public.messages(game_id, receiver_uid, is_read)
    WHERE deleted_at IS NULL;

-- ============================================================
-- 流言表 (rumors)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.rumors (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id uuid NOT NULL UNIQUE REFERENCES public.messages(id) ON DELETE CASCADE,
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    target_uid uuid NOT NULL REFERENCES public.players(id),
    stage int NOT NULL DEFAULT 0 CHECK (stage BETWEEN 0 AND 3),
    spread_count int NOT NULL DEFAULT 0,
    belief_rate float NOT NULL DEFAULT 0.5,
    is_tampered boolean NOT NULL DEFAULT false,
    original_content text,
    expires_at timestamptz NOT NULL DEFAULT (now() + INTERVAL '24 hours'),
    published_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

COMMENT ON TABLE public.rumors IS '流言表';

CREATE INDEX IF NOT EXISTS idx_rumors_game_active ON public.rumors(game_id, stage, expires_at)
    WHERE deleted_at IS NULL AND expires_at > now();

-- ============================================================
-- 挂机监听会话表 (eavesdrop_sessions)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.eavesdrop_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    player_uid uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    scene text NOT NULL,
    scene_key text NOT NULL,
    partner_uid uuid REFERENCES public.players(id),
    is_duo boolean NOT NULL DEFAULT false,
    success_rate_mod real NOT NULL DEFAULT 1.0,
    starts_at timestamptz NOT NULL DEFAULT now(),
    ends_at timestamptz NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'interrupted', 'cancelled')),
    result_count int NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.eavesdrop_sessions IS '挂机监听会话表';

CREATE INDEX IF NOT EXISTS idx_eavesdrop_player_status ON public.eavesdrop_sessions(player_uid, status)
    WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_eavesdrop_scene_count ON public.eavesdrop_sessions(game_id, scene_key, status)
    WHERE status = 'active';

-- ============================================================
-- 情报碎片表 (intel_fragments)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.intel_fragments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    owner_uid uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    source_uid uuid REFERENCES public.players(id),
    session_id uuid REFERENCES public.eavesdrop_sessions(id) ON DELETE SET NULL,
    content text NOT NULL,
    intel_type text NOT NULL,
    scene text,
    scene_key text,
    value_level int NOT NULL DEFAULT 1 CHECK (value_level BETWEEN 1 AND 5),
    status text NOT NULL DEFAULT 'unread',
    is_used boolean NOT NULL DEFAULT false,
    is_sold boolean NOT NULL DEFAULT false,
    is_blocked boolean NOT NULL DEFAULT false,
    blocked_until timestamptz,
    blocked_by uuid REFERENCES public.players(id),
    obtained_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL DEFAULT (now() + INTERVAL '48 hours'),
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

COMMENT ON TABLE public.intel_fragments IS '情报碎片表';

CREATE INDEX IF NOT EXISTS idx_intel_fragments_owner_status ON public.intel_fragments(owner_uid, is_used, is_sold, expires_at)
    INCLUDE (content, intel_type, scene_key, value_level, created_at)
    WHERE is_used = false AND is_sold = false AND deleted_at IS NULL;

-- ============================================================
-- 丫鬟关系表 (maid_relationships)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.maid_relationships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    player_a_uid uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    player_b_uid uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    relation_type text NOT NULL CHECK (relation_type IN ('dui_shi', 'si_yue')),
    status text NOT NULL DEFAULT 'pending',
    initiated_by uuid REFERENCES public.players(id),
    formed_at timestamptz,
    betrayer_uid uuid REFERENCES public.players(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    
    CONSTRAINT maid_rels_unique UNIQUE (game_id, player_a_uid, player_b_uid, relation_type),
    CONSTRAINT maid_rels_different_players CHECK (player_a_uid != player_b_uid)
);

COMMENT ON TABLE public.maid_relationships IS '丫鬟关系表';

CREATE INDEX IF NOT EXISTS idx_maid_rels_player_a ON public.maid_relationships(player_a_uid, status)
    WHERE status IN ('pending', 'active') AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_maid_rels_player_b ON public.maid_relationships(player_b_uid, status)
    WHERE status IN ('pending', 'active') AND deleted_at IS NULL;

-- ============================================================
-- 丫鬟关系共享情报表 (maid_relationship_shared_intel)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.maid_relationship_shared_intel (
    id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    relationship_id uuid NOT NULL REFERENCES public.maid_relationships(id) ON DELETE CASCADE,
    intel_fragment_id uuid NOT NULL REFERENCES public.intel_fragments(id) ON DELETE CASCADE,
    shared_at timestamptz NOT NULL DEFAULT now(),
    shared_by uuid REFERENCES public.players(id),
    
    CONSTRAINT shared_intel_unique UNIQUE (relationship_id, intel_fragment_id)
);

COMMENT ON TABLE public.maid_relationship_shared_intel IS '丫鬟关系共享情报关联表';

CREATE INDEX IF NOT EXISTS idx_shared_intel_relationship ON public.maid_relationship_shared_intel(relationship_id);
CREATE INDEX IF NOT EXISTS idx_shared_intel_fragment ON public.maid_relationship_shared_intel(intel_fragment_id);

-- ============================================================
-- 触发器
-- ============================================================

CREATE TRIGGER trg_games_updated_at
    BEFORE UPDATE ON public.games
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER trg_players_updated_at
    BEFORE UPDATE ON public.players
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER trg_player_stats_updated_at
    BEFORE UPDATE ON public.player_role_stats
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER trg_treasury_updated_at
    BEFORE UPDATE ON public.treasury
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER trg_steward_accounts_updated_at
    BEFORE UPDATE ON public.steward_accounts
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER trg_eavesdrop_updated_at
    BEFORE UPDATE ON public.eavesdrop_sessions
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER trg_maid_rels_updated_at
    BEFORE UPDATE ON public.maid_relationships
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
