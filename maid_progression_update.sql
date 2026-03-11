-- ## 丫鬟逆袭系统补充表结构
-- 用于存储成就、特殊剧情触发、下局偏好及资产转移记录

-- 1. 成就表 (achievements)
CREATE TABLE IF NOT EXISTS achievements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_uid UUID NOT NULL REFERENCES players(id),
    game_id UUID NOT NULL REFERENCES games(id),
    type TEXT NOT NULL, -- 'head_maid', 'concubine', 'redemption'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(player_uid, game_id, type)
);

-- 2. 特殊剧情触发记录 (special_events)
CREATE TABLE IF NOT EXISTS special_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES games(id),
    player_uid UUID NOT NULL REFERENCES players(id),
    event_name TEXT NOT NULL, -- e.g., 'master_special_story'
    triggered_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(game_id, player_uid, event_name)
);

-- 3. 下一局游戏偏好 (next_game_preferences)
CREATE TABLE IF NOT EXISTS next_game_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_uid UUID NOT NULL REFERENCES players(id),
    preference TEXT NOT NULL, -- e.g., 'start_as_master'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(player_uid)
);

-- 4. 资产转移记录表 (asset_transfers)
CREATE TABLE IF NOT EXISTS asset_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES games(id),
    player_uid UUID NOT NULL REFERENCES players(id),
    amount INTEGER NOT NULL DEFAULT 0,
    transferred_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. 清算加成表 (settlement_bonus)
CREATE TABLE IF NOT EXISTS settlement_bonus (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES games(id),
    player_uid UUID NOT NULL REFERENCES players(id),
    bonus_multiplier NUMERIC(3,1) DEFAULT 1.0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(game_id, player_uid)
);

-- 6. 更新 players 表添加 permissions 字段 (如果不存在)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'players' AND column_name = 'permissions') THEN
        ALTER TABLE players ADD COLUMN permissions JSONB DEFAULT '[]';
    END IF;
END $$;

-- 7. 索引优化
CREATE INDEX IF NOT EXISTS idx_achievements_player ON achievements(player_uid);
CREATE INDEX IF NOT EXISTS idx_special_events_player ON special_events(player_uid, event_name);
CREATE INDEX IF NOT EXISTS idx_asset_transfers_player ON asset_transfers(player_uid, game_id);

-- 8. RLS 策略 (简易版)
ALTER TABLE achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE special_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE next_game_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE asset_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE settlement_bonus ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own achievements" ON achievements FOR SELECT USING (player_uid = auth.uid());
CREATE POLICY "Users can view their own special events" ON special_events FOR SELECT USING (player_uid = auth.uid());
CREATE POLICY "Users can manage their own preferences" ON next_game_preferences FOR ALL USING (player_uid = auth.uid());
CREATE POLICY "Users can view their own transfers" ON asset_transfers FOR SELECT USING (player_uid = auth.uid());
