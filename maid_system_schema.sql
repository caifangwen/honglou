-- # 丫鬟小厮系统（Maid/Servant System）数据库架构
-- 适用范围： Godot 4 + Supabase 全栈游戏《大观园》

-- ## 一、枚举类型定义
DO $$ 
BEGIN
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

    -- 监听状态
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'session_status') THEN
        CREATE TYPE session_status AS ENUM (
            'active',           -- 进行中
            'completed',        -- 已完成
            'interrupted'       -- 被中断
        );
    END IF;

    -- 传话/信件状态
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_status') THEN
        CREATE TYPE message_status AS ENUM (
            'pending',          -- 待投递
            'delivered',        -- 已送达
            'intercepted',      -- 被截留
            'tampered'          -- 被篡改
        );
    END IF;

    -- 交易状态
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'trade_status') THEN
        CREATE TYPE trade_status AS ENUM (
            'pending',          -- 待定
            'completed',        -- 完成
            'cancelled'         -- 取消
        );
    END IF;

    -- 丫鬟关系类型
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'maid_relation_type') THEN
        CREATE TYPE maid_relation_type AS ENUM (
            'dui_shi',          -- 对食
            'si_yue'            -- 私约
        );
    END IF;

    -- 丫鬟关系状态
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'maid_relation_status') THEN
        CREATE TYPE maid_relation_status AS ENUM (
            'active',           -- 有效
            'betrayed',         -- 已背叛
            'dissolved'         -- 解散
        );
    END IF;
END $$;

-- ## 二、表结构创建

-- 1. 情报碎片表 (intel_fragments)
-- 注意：如果已存在旧版 intel_fragments，建议备份后执行此脚本，或使用 ALTER 语句。
-- 此处采用 DROP 后重新创建以确保结构完全符合系统设计。
DROP TABLE IF EXISTS intel_fragments CASCADE;
CREATE TABLE intel_fragments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    owner_uid UUID NOT NULL REFERENCES players(id),     -- 当前持有者
    source_uid UUID REFERENCES players(id),             -- 被监听/获取情报的对象
    
    content TEXT NOT NULL,                              -- 情报内容文本
    intel_type intel_type NOT NULL,                     -- 情报类型枚举
    scene scene_location NOT NULL,                      -- 获取场景枚举
    
    value_level INTEGER NOT NULL CHECK (value_level BETWEEN 1 AND 5), -- 价值等级 1-5
    is_used BOOLEAN DEFAULT FALSE,                      -- 是否已使用
    is_sold BOOLEAN DEFAULT FALSE,                      -- 是否已出售
    
    obtained_at TIMESTAMPTZ DEFAULT NOW(),              -- 获取时间
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '48 hours'), -- 情报有效期，48小时
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 挂机监听会话表 (eavesdrop_sessions)
CREATE TABLE IF NOT EXISTS eavesdrop_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    player_uid UUID NOT NULL REFERENCES players(id),
    
    scene scene_location NOT NULL,                      -- 监听场景
    partner_uid UUID REFERENCES players(id),            -- 对食搭档，可为null
    is_duo BOOLEAN DEFAULT FALSE,                       -- 是否双人监听
    
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ends_at TIMESTAMPTZ NOT NULL,                       -- 挂机结束时间
    status session_status DEFAULT 'active',             -- 状态枚举
    result_count INTEGER DEFAULT 0,                     -- 已生成情报碎片数量
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. 传话/信件表 (messages)
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    sender_uid UUID NOT NULL REFERENCES players(id),
    receiver_uid UUID NOT NULL REFERENCES players(id),
    
    original_content TEXT NOT NULL,                     -- 原始内容
    delivered_content TEXT,                             -- 实际送达内容
    carrier_uid UUID REFERENCES players(id),            -- 信使丫鬟uid，可为null
    
    status message_status DEFAULT 'pending',            -- 状态枚举
    is_tampered BOOLEAN DEFAULT FALSE,                  -- 是否被篡改
    is_intercepted BOOLEAN DEFAULT FALSE,               -- 是否被截留
    
    small_fee INTEGER DEFAULT 0,                        -- 信使小费金额
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    delivered_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. 流言表 (rumors)
-- 注意：如果已存在旧版 rumors，建议备份后执行此脚本。
DROP TABLE IF EXISTS rumors CASCADE;
CREATE TABLE rumors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    publisher_uid UUID NOT NULL REFERENCES players(id),
    target_uid UUID NOT NULL REFERENCES players(id),
    
    content TEXT NOT NULL,                              -- 流言内容
    source_fragments JSONB DEFAULT '[]',                -- 使用的情报碎片id数组
    is_merged BOOLEAN DEFAULT FALSE,                    -- 是否为流言嫁接
    
    stage INTEGER DEFAULT 1 CHECK (stage BETWEEN 1 AND 3), -- 发酵阶段 1-3
    stage_1_at TIMESTAMPTZ DEFAULT NOW(),
    stage_2_at TIMESTAMPTZ,
    stage_3_at TIMESTAMPTZ,
    
    is_suppressed BOOLEAN DEFAULT FALSE,                -- 是否被平息
    suppressed_by UUID REFERENCES players(id),          -- 平息者uid
    suppressed_at TIMESTAMPTZ,
    
    damage_multiplier NUMERIC(3,1) DEFAULT 1.0,         -- 伤害倍率，合并流言通常为2.0
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. 情报交易记录表 (intel_trades)
CREATE TABLE IF NOT EXISTS intel_trades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    seller_uid UUID NOT NULL REFERENCES players(id),
    buyer_uid UUID NOT NULL REFERENCES players(id),
    fragment_id UUID NOT NULL REFERENCES intel_fragments(id),
    
    price_silver INTEGER DEFAULT 0,                     -- 银两价格
    price_qi INTEGER DEFAULT 0,                         -- 气数价格
    status trade_status DEFAULT 'pending',
    traded_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. 丫鬟关系表 (maid_relationships)
CREATE TABLE IF NOT EXISTS maid_relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    player_a_uid UUID NOT NULL REFERENCES players(id),
    player_b_uid UUID NOT NULL REFERENCES players(id),
    
    relation_type maid_relation_type NOT NULL,          -- 关系类型
    status maid_relation_status DEFAULT 'active',       -- 状态
    betrayer_uid UUID REFERENCES players(id),           -- 背叛者uid
    
    shared_intel_ids JSONB DEFAULT '[]',                -- 共同获取的情报碎片id列表
    formed_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_maid_rel UNIQUE(game_id, player_a_uid, player_b_uid, relation_type)
);

-- 7. 丫鬟对主子忠诚度表 (maid_loyalty)
CREATE TABLE IF NOT EXISTS maid_loyalty (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    maid_uid UUID NOT NULL REFERENCES players(id),
    master_uid UUID NOT NULL REFERENCES players(id),
    
    loyalty_score INTEGER DEFAULT 50 CHECK (loyalty_score BETWEEN 0 AND 100), -- 忠诚度 0-100
    abandon_count INTEGER DEFAULT 0,                    -- 背叛主子次数
    is_disgraced BOOLEAN DEFAULT FALSE,                 -- 是否声名狼藉
    
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(game_id, maid_uid, master_uid)
);

-- ## 三、索引优化
-- 为高频查询字段加索引 (game_id, player_uid, status, stage)
CREATE INDEX IF NOT EXISTS idx_intel_fragments_game_owner ON intel_fragments(game_id, owner_uid);
CREATE INDEX IF NOT EXISTS idx_eavesdrop_sessions_player ON eavesdrop_sessions(player_uid, status);
CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_uid, status);
CREATE INDEX IF NOT EXISTS idx_rumors_game_stage ON rumors(game_id, stage);
CREATE INDEX IF NOT EXISTS idx_rumors_target ON rumors(target_uid);
CREATE INDEX IF NOT EXISTS idx_intel_trades_buyer ON intel_trades(buyer_uid);
CREATE INDEX IF NOT EXISTS idx_maid_relationships_players ON maid_relationships(player_a_uid, player_b_uid);
CREATE INDEX IF NOT EXISTS idx_maid_loyalty_maid ON maid_loyalty(maid_uid);

-- ## 四、Row Level Security (RLS) 配置

-- 启用 RLS
ALTER TABLE intel_fragments ENABLE ROW LEVEL SECURITY;
ALTER TABLE eavesdrop_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE rumors ENABLE ROW LEVEL SECURITY;
ALTER TABLE intel_trades ENABLE ROW LEVEL SECURITY;
ALTER TABLE maid_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE maid_loyalty ENABLE ROW LEVEL SECURITY;

-- 辅助函数：获取当前登录用户的玩家 ID
-- 如果 players 表结构中 auth_uid 是关联 auth.users 的字段
CREATE OR REPLACE FUNCTION get_my_player_id()
RETURNS UUID AS $$
    SELECT id FROM players WHERE auth_uid = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER;

-- 1. intel_fragments: 只能读取和操作自己的情报
DROP POLICY IF EXISTS "Players can view their own intel" ON intel_fragments;
CREATE POLICY "Players can view their own intel" ON intel_fragments
    FOR SELECT USING (owner_uid = get_my_player_id());

DROP POLICY IF EXISTS "Players can update their own intel" ON intel_fragments;
CREATE POLICY "Players can update their own intel" ON intel_fragments
    FOR UPDATE USING (owner_uid = get_my_player_id());

-- 2. eavesdrop_sessions: 只能查看自己的监听会话
DROP POLICY IF EXISTS "Players can view their own sessions" ON eavesdrop_sessions;
CREATE POLICY "Players can view their own sessions" ON eavesdrop_sessions
    FOR SELECT USING (player_uid = get_my_player_id() OR partner_uid = get_my_player_id());

DROP POLICY IF EXISTS "Players can manage their own sessions" ON eavesdrop_sessions;
CREATE POLICY "Players can manage their own sessions" ON eavesdrop_sessions
    FOR ALL USING (player_uid = get_my_player_id());

-- 3. messages: 发送者、接收者、信使可以查看
DROP POLICY IF EXISTS "Involved players can view messages" ON messages;
CREATE POLICY "Involved players can view messages" ON messages
    FOR SELECT USING (
        sender_uid = get_my_player_id() OR 
        receiver_uid = get_my_player_id() OR 
        carrier_uid = get_my_player_id()
    );

DROP POLICY IF EXISTS "Senders can insert messages" ON messages;
CREATE POLICY "Senders can insert messages" ON messages
    FOR INSERT WITH CHECK (sender_uid = get_my_player_id());

-- 4. rumors: 广场公开，所有人可看；发布者可管理
DROP POLICY IF EXISTS "Rumors are public" ON rumors;
CREATE POLICY "Rumors are public" ON rumors
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Publishers can manage their rumors" ON rumors;
CREATE POLICY "Publishers can manage their rumors" ON rumors
    FOR ALL USING (publisher_uid = get_my_player_id());

-- 5. intel_trades: 买卖双方可看
DROP POLICY IF EXISTS "Traders can view their trades" ON intel_trades;
CREATE POLICY "Traders can view their trades" ON intel_trades
    FOR SELECT USING (seller_uid = get_my_player_id() OR buyer_uid = get_my_player_id());

-- 6. maid_relationships: 关系双方可看
DROP POLICY IF EXISTS "Maids can view their relationships" ON maid_relationships;
CREATE POLICY "Maids can view their relationships" ON maid_relationships
    FOR SELECT USING (player_a_uid = get_my_player_id() OR player_b_uid = get_my_player_id());

-- 7. maid_loyalty: 丫鬟和主子可看
DROP POLICY IF EXISTS "Involved parties can view loyalty" ON maid_loyalty;
CREATE POLICY "Involved parties can view loyalty" ON maid_loyalty
    FOR SELECT USING (maid_uid = get_my_player_id() OR master_uid = get_my_player_id());

-- ## 五、触发器 (自动更新 last_updated)
CREATE OR REPLACE FUNCTION update_last_updated_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_updated = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_maid_loyalty_updated ON maid_loyalty;
CREATE TRIGGER trg_maid_loyalty_updated
    BEFORE UPDATE ON maid_loyalty
    FOR EACH ROW EXECUTE FUNCTION update_last_updated_column();
