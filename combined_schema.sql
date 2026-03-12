-- ################################################################################
-- ## 《红楼回忆志》（大观园）全量数据库初始化脚本
-- ## 合并时间：2026-03-12
-- ## 包含模块：核心系统、时间系统、精力系统、流言系统、留言系统、银库系统、丫鬟系统、管家系统、逆袭系统
-- ################################################################################

-- #################### SECTION 0: 基础设置与扩展 ####################
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

-- #################### SECTION 1: 枚举类型定义 ####################
DO $$ 
BEGIN
    -- 角色类型
    -- 已在 players 表中使用 check 约束，此处不再定义枚举

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
            'account_leak',    -- 账目漏洞
            'private_action',  -- 私人行动
            'gift_record',     -- 赠礼记录
            'visitor_info',    -- 访客信息
            'elder_favor'      -- 元老喜好
        );
    END IF;

    -- 场景地点
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'scene_location') THEN
        CREATE TYPE scene_location AS ENUM (
            'yi_hong_yuan',     -- 怡红院
            'treasury_back',    -- 管家后账房
            'bridge',           -- 蜂腰桥
            'gate',             -- 荣国府大门
            'elder_room'        -- 贾母处
        );
    END IF;

    -- 会话状态
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'session_status') THEN
        CREATE TYPE session_status AS ENUM ('active', 'completed', 'interrupted');
    END IF;

    -- 消息/投递状态
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

-- #################### SECTION 2: 核心表结构 (Games & Players) ####################

-- 1. games 表：全局游戏局状态
CREATE TABLE IF NOT EXISTS public.games (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    status text DEFAULT 'active' CHECK (status IN ('active', 'crisis', 'purge', 'ended')),
    
    -- 时间系统所需字段
    start_timestamp bigint NOT NULL,             -- Unix 时间戳 (秒)
    end_timestamp bigint,
    speed_multiplier float DEFAULT 1.0,
    
    -- 家族全局指标
    deficit_value float DEFAULT 0.0,             -- 家族亏空值 0~100
    conflict_value float DEFAULT 0.0,            -- 家族内耗值 0~100
    
    current_day int DEFAULT 1,
    started_at timestamptz DEFAULT now(),
    ended_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- 2. players 表：玩家基础数据与属性
CREATE TABLE IF NOT EXISTS public.players (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_uid uuid UNIQUE NOT NULL REFERENCES auth.users(id),
    username text UNIQUE,                        -- 用户名登录支持

    -- 角色扮演
    display_name text NOT NULL,
    character_name text,                         -- 扮演的角色名
    role_class text NOT NULL CHECK (role_class IN ('steward', 'master', 'servant', 'elder', 'guest')),

    -- 当前局游戏ID
    current_game_id uuid REFERENCES public.games(id),

    -- 数值属性
    stamina int DEFAULT 6,                       -- 精力
    stamina_max int DEFAULT 6,
    stamina_refreshed_at timestamptz DEFAULT now(),

    qi_points int DEFAULT 100,                   -- 气数 (原 qi_shu)
    silver int DEFAULT 0,                        -- 个人银两 (公款/私款视逻辑而定)
    private_silver int DEFAULT 0,                -- 个人私产
    face_value int DEFAULT 50,                   -- 体面值
    prestige int DEFAULT 10,                     -- 名望值
    loyalty int DEFAULT 50,                      -- 忠诚度
    reputation int DEFAULT 50,                   -- 声望
    karma_score int DEFAULT 0,                   -- 因果值

    -- 状态与记录
    is_disgraced boolean DEFAULT false,          -- 声名狼藉
    betrayal_count int DEFAULT 0,                -- 背叛次数
    permissions jsonb DEFAULT '[]',              -- 权限列表

    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- #################### SECTION 3: 银库与财务系统 ####################

-- 1. treasury 表：公中银库
CREATE TABLE IF NOT EXISTS public.treasury (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid NOT NULL UNIQUE REFERENCES public.games(id) ON DELETE CASCADE,
    
    -- 账目
    total_silver int DEFAULT 10000,              -- 总银两
    daily_budget int DEFAULT 1000,               -- 每日预算
    public_balance numeric(10,2) DEFAULT 10000,  -- 明账余额
    real_balance numeric(10,2) DEFAULT 10000,    -- 暗账余额
    
    prosperity_level int DEFAULT 1 CHECK (prosperity_level BETWEEN 1 AND 10),
    deficit_rate float DEFAULT 0.0 CHECK (deficit_rate BETWEEN 0.0 AND 1.0),
    
    last_allocation_day int DEFAULT 0,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- 2. ledger_entries 表：账目流水
CREATE TABLE IF NOT EXISTS public.ledger_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id),
    treasury_id uuid NOT NULL REFERENCES public.treasury(id),
    ledger_type text NOT NULL CHECK (ledger_type IN ('public', 'private')),
    entry_type text NOT NULL CHECK (entry_type IN ('allocation', 'deduction', 'procurement', 'advance', 'bribe', 'reward')),
    amount numeric(10,2) NOT NULL,
    actor_id uuid REFERENCES public.players(id),
    target_id uuid REFERENCES public.players(id),
    note text,
    created_at timestamptz DEFAULT now()
);

-- 3. allowance_records 表：月例发放记录
CREATE TABLE IF NOT EXISTS public.allowance_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    player_id uuid REFERENCES public.players(id), -- 领用人
    issued_by uuid REFERENCES public.players(id), -- 发放人 (管家)
    amount_public int NOT NULL,                  -- 名义金额
    amount_actual int NOT NULL,                  -- 实际金额
    withheld_amount int DEFAULT 0,               -- 克扣金额
    is_public boolean DEFAULT true,
    issued_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now()
);

-- 4. deficit_log 表：亏空变动日志
CREATE TABLE IF NOT EXISTS public.deficit_log (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid REFERENCES public.games(id) ON DELETE CASCADE,
    operated_at timestamptz DEFAULT now(),
    operated_by uuid REFERENCES public.players(id),
    delta_amount int NOT NULL,
    new_deficit_percent float NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- #################### SECTION 4: 时间与精力系统 ####################

-- 1. game_time_events 表：时间节点触发日志
CREATE TABLE IF NOT EXISTS public.game_time_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid REFERENCES public.games(id) ON DELETE CASCADE,
    event_type text NOT NULL CHECK (event_type IN ('day_start', 'xun_end', 'month_end', 'event_trigger')),
    game_day int NOT NULL,
    game_xun int NOT NULL,
    triggered_at bigint NOT NULL,
    payload jsonb DEFAULT '{}',
    created_at timestamptz DEFAULT now()
);

-- 2. player_stamina 表：专门的精力管理 (部分逻辑已整合入 players)
-- 某些逻辑可能仍依赖此独立表，保持兼容性
CREATE TABLE IF NOT EXISTS public.player_stamina (
    player_id uuid PRIMARY KEY REFERENCES public.players(id) ON DELETE CASCADE,
    game_id uuid REFERENCES public.games(id) ON DELETE CASCADE,
    current_stamina int DEFAULT 0,
    last_refresh_timestamp bigint NOT NULL,
    stamina_role text DEFAULT 'maid' CHECK (stamina_role IN ('steward', 'maid')),
    max_stamina int DEFAULT 8
);

-- #################### SECTION 5: 流言与留言系统 ####################

-- 1. rumors 表：流言系统
CREATE TABLE IF NOT EXISTS public.rumors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    publisher_uid UUID NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    target_uid UUID NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    
    content TEXT NOT NULL,
    source_type TEXT,                            -- 'intel_fragment' | 'freewrite'
    intel_fragment_ids UUID[],                   -- 关联的情报碎片
    is_grafted BOOLEAN DEFAULT FALSE,            -- 是否嫁接
    credibility FLOAT DEFAULT 1.0,
    
    stage INT DEFAULT 1 CHECK (stage BETWEEN 1 AND 3),
    published_at TIMESTAMPTZ DEFAULT NOW(),
    stage2_at TIMESTAMPTZ,
    stage3_at TIMESTAMPTZ,
    
    is_suppressed BOOLEAN DEFAULT FALSE,
    suppressed_by UUID REFERENCES public.players(id),
    suppressed_at TIMESTAMPTZ,
    suppress_method TEXT,
    
    publisher_exposed BOOLEAN DEFAULT FALSE,
    exposure_method TEXT,
    penalty_applied BOOLEAN DEFAULT FALSE,
    
    damage_multiplier NUMERIC(3,1) DEFAULT 1.0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. rumor_events 表：流言事件日志
CREATE TABLE IF NOT EXISTS public.rumor_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rumor_id UUID NOT NULL REFERENCES public.rumors(id) ON DELETE CASCADE,
    actor_uid UUID NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    event_data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. messages 表：留言与信件
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    sender_uid UUID REFERENCES public.players(id),
    receiver_uid UUID REFERENCES public.players(id),
    
    content TEXT DEFAULT '',
    original_content TEXT,                       -- 原始内容 (用于篡改逻辑)
    delivered_content TEXT,                      -- 送达内容
    message_type TEXT NOT NULL DEFAULT 'private', -- 'private'|'rumor'|'batch_order'|'system'
    
    is_tampered BOOLEAN DEFAULT FALSE,
    is_intercepted BOOLEAN DEFAULT FALSE,
    is_read BOOLEAN DEFAULT FALSE,
    
    carrier_uid UUID REFERENCES public.players(id),
    small_fee INTEGER DEFAULT 0,
    stamina_cost INT DEFAULT 0,
    attachments JSONB DEFAULT '[]',
    
    stage INT DEFAULT 0,                         -- 演化阶段
    expires_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    delivered_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. message_reactions & inbox_status
CREATE TABLE IF NOT EXISTS public.message_reactions ( 
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), 
  message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE, 
  reactor_uid UUID REFERENCES public.players(id), 
  reaction_type TEXT NOT NULL,  -- 'like' / 'dislike' / 'report' / 'endorse' 
  created_at TIMESTAMPTZ DEFAULT NOW(), 
  UNIQUE(message_id, reactor_uid, reaction_type) 
); 

CREATE TABLE IF NOT EXISTS public.inbox_status ( 
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), 
  player_uid UUID REFERENCES public.players(id), 
  message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE, 
  is_archived BOOLEAN DEFAULT FALSE, 
  is_starred BOOLEAN DEFAULT FALSE, 
  read_at TIMESTAMPTZ, 
  UNIQUE(player_uid, message_id) 
); 

-- #################### SECTION 6: 情报与监听系统 ####################

-- 1. intel_fragments 表：情报碎片
CREATE TABLE IF NOT EXISTS public.intel_fragments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    owner_uid UUID NOT NULL REFERENCES public.players(id),
    source_uid UUID REFERENCES public.players(id),
    
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

-- 2. eavesdrop_sessions 表：挂机监听
CREATE TABLE IF NOT EXISTS public.eavesdrop_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    player_uid UUID NOT NULL REFERENCES public.players(id),
    
    scene scene_location NOT NULL,
    partner_uid UUID REFERENCES public.players(id),
    is_duo BOOLEAN DEFAULT FALSE,
    
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ends_at TIMESTAMPTZ NOT NULL,
    status session_status DEFAULT 'active',
    result_count INTEGER DEFAULT 0,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. intel_trades 表：情报交易
CREATE TABLE IF NOT EXISTS public.intel_trades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    seller_uid UUID NOT NULL REFERENCES public.players(id),
    buyer_uid UUID NOT NULL REFERENCES public.players(id),
    fragment_id UUID NOT NULL REFERENCES public.intel_fragments(id),
    
    price_silver INTEGER DEFAULT 0,
    price_qi INTEGER DEFAULT 0,
    status trade_status DEFAULT 'pending',
    traded_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- #################### SECTION 7: 社交关系与地图 ####################

-- 1. relationships 表：核心关系网
CREATE TABLE IF NOT EXISTS public.relationships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id),
    player_a uuid NOT NULL REFERENCES public.players(id),
    player_b uuid NOT NULL REFERENCES public.players(id),
    relation_type text NOT NULL CHECK (relation_type IN ('ally', 'rival', 'confidant', 'admirer', 'duo_wiretap', 'betrayed')),
    initiated_by uuid REFERENCES public.players(id),
    is_mutual bool DEFAULT false,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(game_id, player_a, player_b, relation_type)
);

-- 2. maid_relationships 表：丫鬟专属关系 (对食/私约)
CREATE TABLE IF NOT EXISTS public.maid_relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    player_a_uid UUID NOT NULL REFERENCES public.players(id),
    player_b_uid UUID NOT NULL REFERENCES public.players(id),
    
    relation_type maid_relation_type NOT NULL,
    status maid_relation_status DEFAULT 'active',
    betrayer_uid UUID REFERENCES public.players(id),
    
    shared_intel_ids JSONB DEFAULT '[]',
    formed_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_maid_rel UNIQUE(game_id, player_a_uid, player_b_uid, relation_type)
);

-- 3. maid_loyalty 表：忠诚度
CREATE TABLE IF NOT EXISTS public.maid_loyalty (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    maid_uid UUID NOT NULL REFERENCES public.players(id),
    master_uid UUID NOT NULL REFERENCES public.players(id),
    
    loyalty_score INTEGER DEFAULT 50 CHECK (loyalty_score BETWEEN 0 AND 100),
    abandon_count INTEGER DEFAULT 0,
    is_disgraced BOOLEAN DEFAULT FALSE,
    
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(game_id, maid_uid, master_uid)
);

-- 4. map_locations 表：地点状态
CREATE TABLE IF NOT EXISTS public.map_locations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id),
    location_key text NOT NULL,
    location_name text NOT NULL,
    wiretapping_players uuid[] DEFAULT '{}',
    rare_intel_triggered bool DEFAULT false,
    rare_intel_reset_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(game_id, location_key)
);

-- #################### SECTION 8: 管家与审批系统 ####################

-- 1. steward_accounts 表：管家个人账目
CREATE TABLE IF NOT EXISTS public.steward_accounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.treasury(game_id),
    steward_uid uuid NOT NULL REFERENCES public.players(id),
    public_ledger jsonb DEFAULT '[]',
    private_ledger jsonb DEFAULT '[]',
    private_assets integer DEFAULT 0,
    prestige integer DEFAULT 50 CHECK (prestige BETWEEN 0 AND 100),
    action_route steward_route DEFAULT 'undecided',
    assets_transferred boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    UNIQUE(game_id, steward_uid)
);

-- 2. action_approvals 表：行动批条
CREATE TABLE IF NOT EXISTS public.action_approvals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.treasury(game_id),
    steward_uid uuid NOT NULL REFERENCES public.players(id),
    action_type action_type NOT NULL,
    target_uid uuid REFERENCES public.players(id),
    stamina_cost integer NOT NULL,
    params jsonb DEFAULT '{}',
    status approval_status DEFAULT 'pending',
    executed_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- 3. audit_cases 表：查账案件
CREATE TABLE IF NOT EXISTS public.audit_cases (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.treasury(game_id),
    plaintiff_uid uuid NOT NULL REFERENCES public.players(id),
    defendant_uid uuid NOT NULL REFERENCES public.players(id),
    evidence_fragments jsonb[] DEFAULT '{}',
    status audit_status DEFAULT 'filed',
    verdict audit_verdict,
    deadline timestamptz NOT NULL,
    elder_notes text,
    pending_evidence_removal uuid,
    plaintiff_credibility integer DEFAULT 100,
    counter_accused boolean DEFAULT false,
    new_target uuid,
    created_at timestamptz DEFAULT now()
);

-- #################### SECTION 9: 任务、成就与清算 ####################

-- 1. actions 表：通用行动队列
CREATE TABLE IF NOT EXISTS public.actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid NOT NULL REFERENCES public.games(id),
  actor_id uuid NOT NULL REFERENCES public.players(id),
  action_type text NOT NULL,
  stamina_cost int NOT NULL,
  target_id uuid REFERENCES public.players(id),
  payload jsonb DEFAULT '{}',
  status text DEFAULT 'pending' CHECK (status IN ('pending','resolved','cancelled')),
  resolved_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- 2. achievements 表：成就记录
CREATE TABLE IF NOT EXISTS public.achievements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_uid UUID NOT NULL REFERENCES public.players(id),
    game_id UUID NOT NULL REFERENCES public.games(id),
    type TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(player_uid, game_id, type)
);

-- 3. special_events 表：特殊剧情记录
CREATE TABLE IF NOT EXISTS public.special_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id),
    player_uid UUID NOT NULL REFERENCES public.players(id),
    event_name TEXT NOT NULL,
    triggered_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(game_id, player_uid, event_name)
);

-- 4. asset_transfers 表：资产转移
CREATE TABLE IF NOT EXISTS public.asset_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public.games(id),
    player_uid UUID NOT NULL REFERENCES public.players(id),
    amount INTEGER NOT NULL DEFAULT 0,
    transferred_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. events 表：突发大事件
CREATE TABLE IF NOT EXISTS public.events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid NOT NULL REFERENCES public.games(id),
  event_type text NOT NULL,
  status text DEFAULT 'active' CHECK (status IN ('active','resolving','ended')),
  deadline_at timestamptz,
  payload jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- #################### SECTION 10: 辅助函数与 RPC ####################

-- 1. 获取当前玩家 ID
CREATE OR REPLACE FUNCTION public.get_my_player_id()
RETURNS UUID AS $$
    SELECT id FROM public.players WHERE auth_uid = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER;

-- 2. 根据用户名获取 Email (支持登录)
CREATE OR REPLACE FUNCTION public.get_email_by_username(p_username TEXT)
RETURNS TEXT AS $$
DECLARE
    v_email TEXT;
BEGIN
    SELECT u.email INTO v_email
    FROM auth.users u
    JOIN public.players p ON p.auth_uid = u.id
    WHERE p.username = p_username;
    RETURN v_email;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 获取当前游戏时间的各种维度
CREATE OR REPLACE FUNCTION public.get_current_game_time(p_game_id uuid)
RETURNS json AS $$
DECLARE
    v_start bigint;
    v_speed float;
    v_now bigint;
    v_elapsed_game bigint;
    v_day int;
    v_xun int;
    v_month int;
BEGIN
    SELECT start_timestamp, speed_multiplier INTO v_start, v_speed 
    FROM public.games WHERE id = p_game_id;
    v_now := extract(epoch from now())::bigint;
    v_elapsed_game := (v_now - v_start) * v_speed;
    v_day := (v_elapsed_game / 7200) + 1;
    v_xun := (v_elapsed_game / 72000) + 1;
    v_month := (v_elapsed_game / 216000) + 1;
    RETURN json_build_object(
        'game_day', v_day,
        'game_xun', v_xun,
        'game_month', v_month,
        'day_progress', (v_elapsed_game % 7200) / 7200.0,
        'elapsed_game_seconds', v_elapsed_game
    );
END;
$$ LANGUAGE plpgsql;

-- 4. 计算当前精力 (含自动恢复)
CREATE OR REPLACE FUNCTION public.calculate_stamina(p_player_id uuid, p_game_id uuid)
RETURNS int AS $$
DECLARE
    v_last_ts bigint;
    v_current int;
    v_max int;
    v_speed float;
    v_now bigint;
    v_recovered int;
    v_interval bigint := 7200;
BEGIN
    SELECT current_stamina, last_refresh_timestamp, max_stamina INTO v_current, v_last_ts, v_max
    FROM public.player_stamina WHERE player_id = p_player_id;
    SELECT speed_multiplier INTO v_speed FROM public.games WHERE id = p_game_id;
    v_now := extract(epoch from now())::bigint;
    v_recovered := floor(((v_now - v_last_ts) * v_speed) / v_interval);
    RETURN LEAST(v_current + v_recovered, v_max);
END;
$$ LANGUAGE plpgsql;

-- 5. 情报交易事务处理
CREATE OR REPLACE FUNCTION public.purchase_intel_transaction(
    p_trade_id UUID,
    p_buyer_uid UUID,
    p_seller_uid UUID,
    p_fragment_id UUID,
    p_price_silver INT,
    p_price_qi INT
) RETURNS JSON AS $$
DECLARE
    v_buyer_silver INT;
    v_buyer_qi INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM intel_trades WHERE id = p_trade_id AND status = 'pending') THEN
        RETURN json_build_object('success', false, 'error', '交易已失效');
    END IF;
    SELECT silver, qi_points INTO v_buyer_silver, v_buyer_qi FROM players WHERE id = p_buyer_uid;
    IF p_price_silver > 0 AND v_buyer_silver < p_price_silver THEN
        RETURN json_build_object('success', false, 'error', '银两不足');
    END IF;
    IF p_price_qi > 0 AND v_buyer_qi < p_price_qi THEN
        RETURN json_build_object('success', false, 'error', '气数不足');
    END IF;
    UPDATE players SET silver = silver - p_price_silver, qi_points = qi_points - p_price_qi WHERE id = p_buyer_uid;
    UPDATE players SET silver = silver + p_price_silver, qi_points = qi_points + p_price_qi WHERE id = p_seller_uid;
    UPDATE intel_fragments SET owner_uid = p_buyer_uid, is_sold = true WHERE id = p_fragment_id;
    UPDATE intel_trades SET status = 'completed', buyer_uid = p_buyer_uid, traded_at = NOW() WHERE id = p_trade_id;
    RETURN json_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- 6. 修改银库余额 (管家调用)
CREATE OR REPLACE FUNCTION public.decrement_treasury(g_id uuid, amount integer)
RETURNS void AS $$
BEGIN
    UPDATE treasury SET total_silver = total_silver - amount, updated_at = now() WHERE game_id = g_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- #################### SECTION 11: RLS 策略配置 ####################

-- 开启所有表的 RLS
ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treasury ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.allowance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deficit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rumors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intel_fragments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.steward_accounts ENABLE ROW LEVEL SECURITY;

-- 简化示例：开发环境开放读取
CREATE POLICY "dev_read_all" ON public.games FOR SELECT USING (true);
CREATE POLICY "dev_read_all" ON public.players FOR SELECT USING (true);
CREATE POLICY "dev_read_all" ON public.treasury FOR SELECT USING (true);
CREATE POLICY "dev_read_all" ON public.steward_accounts FOR SELECT USING (true);
CREATE POLICY "dev_read_all" ON public.allowance_records FOR SELECT USING (true);

-- 玩家操作策略
DROP POLICY IF EXISTS "players_manage_self" ON public.players;
CREATE POLICY "players_manage_self" ON public.players 
    FOR ALL 
    TO authenticated 
    USING (auth.uid() = auth_uid)
    WITH CHECK (auth.uid() = auth_uid);

-- 银库与账目操作 (开发环境允许 authenticated 插入)
CREATE POLICY "auth_insert_treasury" ON public.treasury FOR INSERT WITH CHECK (true);
CREATE POLICY "auth_insert_steward_accounts" ON public.steward_accounts FOR INSERT WITH CHECK (true);
CREATE POLICY "auth_insert_ledger" ON public.ledger_entries FOR INSERT WITH CHECK (true);

CREATE POLICY "messages_involved" ON public.messages FOR SELECT USING (sender_uid = get_my_player_id() OR receiver_uid = get_my_player_id() OR carrier_uid = get_my_player_id());
CREATE POLICY "intel_owner" ON public.intel_fragments FOR SELECT USING (owner_uid = get_my_player_id());

-- 授权
GRANT ALL ON public.players TO authenticated;
GRANT ALL ON public.messages TO authenticated;
GRANT ALL ON public.intel_fragments TO authenticated;
GRANT ALL ON public.treasury TO authenticated;
GRANT ALL ON public.steward_accounts TO authenticated;
GRANT ALL ON public.ledger_entries TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_by_username(TEXT) TO anon, authenticated;

-- #################### SECTION 12: 初始/测试数据 ####################

-- 1. 默认游戏局
INSERT INTO public.games (id, start_timestamp, status, speed_multiplier, deficit_value)
VALUES ('00000000-0000-0000-0000-000000000001', extract(epoch from now())::bigint, 'active', 1.0, 0.0)
ON CONFLICT (id) DO NOTHING;

-- 2. 默认银库
INSERT INTO public.treasury (game_id, total_silver, daily_budget, prosperity_level, deficit_rate)
VALUES ('00000000-0000-0000-0000-000000000001', 50000, 2000, 8, 0.0)
ON CONFLICT (game_id) DO NOTHING;

-- 3. 初始地点
INSERT INTO public.map_locations (game_id, location_key, location_name) 
VALUES
  ('00000000-0000-0000-0000-000000000001', 'yi_hong_yuan', '怡红院后窗'),
  ('00000000-0000-0000-0000-000000000001', 'treasury_room', '管家后账房'),
  ('00000000-0000-0000-0000-000000000001', 'bridge', '蜂腰桥'),
  ('00000000-0000-0000-0000-000000000001', 'gate', '荣国府大门'),
  ('00000000-0000-0000-0000-000000000001', 'grandma', '贾母处')
ON CONFLICT DO NOTHING;
