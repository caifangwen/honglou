-- 20260311_rumor_system.sql
-- 实现完整的流言系统架构

-- 1. 创建流言主表
-- 注意：为了确保结构完全符合系统设计，如果已存在旧版 rumors，我们先删除它
DROP TABLE IF EXISTS rumors CASCADE;

CREATE TABLE rumors ( 
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), 
  game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE, 
  publisher_uid UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,   -- 真实发布者
  target_uid UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,      -- 受害目标 
  
  content TEXT NOT NULL,           -- 流言正文（最多150字） 
  source_type TEXT NOT NULL,       -- 'intel_fragment' | 'freewrite' 
  intel_fragment_ids UUID[],       -- 关联的情报碎片ID（嫁接时为2个） 
  is_grafted BOOLEAN DEFAULT FALSE, -- 是否为嫁接流言 
  credibility FLOAT DEFAULT 1.0,   -- 可信度 0.5–2.0 
  
  stage INT DEFAULT 1,             -- 1=口耳相传 2=人尽皆知 3=板上钉钉 
  published_at TIMESTAMPTZ DEFAULT NOW(), 
  stage2_at TIMESTAMPTZ,           -- 预计进入阶段2的时间 
  stage3_at TIMESTAMPTZ,           -- 预计进入阶段3的时间 
  
  is_suppressed BOOLEAN DEFAULT FALSE,  -- 是否被压下 
  suppressed_by UUID REFERENCES players(id), -- 压下者uid
  suppressed_at TIMESTAMPTZ, 
  suppress_method TEXT,            -- 'self_suppress' | 'steward_quell' | 'elder_order' 
  
  publisher_exposed BOOLEAN DEFAULT FALSE,  -- 发布者是否已暴露 
  exposure_method TEXT,            -- 'mirror_item' | 'steward_trace' | 'elder_order' 
  
  penalty_applied BOOLEAN DEFAULT FALSE,   -- 最终惩罚是否已结算 
  
  created_at TIMESTAMPTZ DEFAULT NOW() 
); 

-- 2. 创建流言操作日志表
DROP TABLE IF EXISTS rumor_events CASCADE;
CREATE TABLE rumor_events ( 
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), 
  rumor_id UUID NOT NULL REFERENCES rumors(id) ON DELETE CASCADE, 
  actor_uid UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE, 
  event_type TEXT NOT NULL, 
  -- 'published' | 'stage_advanced' | 'self_suppressed' | 
  -- 'steward_quelled' | 'publisher_exposed' | 'penalty_applied' 
  event_data JSONB,                -- 附加数据
  created_at TIMESTAMPTZ DEFAULT NOW() 
); 

-- 3. 修改 players 表，新增字段（如果不存在）
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'players' AND column_name = 'reputation') THEN
        ALTER TABLE players ADD COLUMN reputation INT DEFAULT 50;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'players' AND column_name = 'karma_score') THEN
        ALTER TABLE players ADD COLUMN karma_score INT DEFAULT 0;
    END IF;

    -- 注意：stamina, face_value, qi_points 在 schema 中已存在或有类似字段
    -- 我们统一使用 user 指定的名称或保持一致性
    -- Schema 中 qi_shu 对应 qi_points
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'players' AND column_name = 'qi_points') THEN
        IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'players' AND column_name = 'qi_shu') THEN
            ALTER TABLE players RENAME COLUMN qi_shu TO qi_points;
        ELSE
            ALTER TABLE players ADD COLUMN qi_points INT DEFAULT 100;
        END IF;
    END IF;
END $$;

-- 4. RLS 策略
ALTER TABLE rumors ENABLE ROW LEVEL SECURITY;
ALTER TABLE rumor_events ENABLE ROW LEVEL SECURITY;

-- 辅助函数：获取当前玩家 ID
CREATE OR REPLACE FUNCTION get_my_player_id()
RETURNS UUID AS $$
    SELECT id FROM players WHERE auth_uid = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER;

-- 流言可见性策略：
-- 1. 发布者可以查看自己发布的流言
-- 2. 目标玩家可以查看针对自己的流言
-- 3. 所有人可以查看 stage >= 2 且未被压制的流言（匿名，除非 publisher_exposed=true）
-- 4. 元老角色可以查看所有流言及发布者

CREATE POLICY rumors_select_policy ON rumors
  FOR SELECT
  USING (
    publisher_uid = get_my_player_id() OR
    target_uid = get_my_player_id() OR
    (stage >= 2 AND is_suppressed = FALSE) OR
    EXISTS (
      SELECT 1 FROM players 
      WHERE id = get_my_player_id() AND role_class = 'elder'
    )
  );

-- 流言操作日志策略
CREATE POLICY rumor_events_select_policy ON rumor_events
  FOR SELECT
  USING (
    actor_uid = get_my_player_id() OR
    EXISTS (
      SELECT 1 FROM rumors WHERE id = rumor_id AND (publisher_uid = get_my_player_id() OR target_uid = get_my_player_id())
    ) OR
    EXISTS (
      SELECT 1 FROM players 
      WHERE id = get_my_player_id() AND role_class = 'elder'
    )
  );

-- 5. 索引优化
CREATE INDEX IF NOT EXISTS idx_rumors_game_id ON rumors(game_id);
CREATE INDEX IF NOT EXISTS idx_rumors_target_uid ON rumors(target_uid);
CREATE INDEX IF NOT EXISTS idx_rumors_stage ON rumors(stage);
CREATE INDEX IF NOT EXISTS idx_rumors_is_suppressed ON rumors(is_suppressed);
