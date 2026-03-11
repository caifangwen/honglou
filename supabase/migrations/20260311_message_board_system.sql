-- 修正留言系统迁移脚本
-- 解决与 maid_system_schema.sql 中已存在的 messages 表结构冲突问题

-- 1. 确保 messages 表具备留言面板所需的字段
DO $$ 
BEGIN 
    -- 如果表不存在则创建（基础结构）
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'messages') THEN
        CREATE TABLE messages (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
            sender_uid UUID REFERENCES players(id),     -- 发送者（关联 players.id，NULL = 系统消息）
            receiver_uid UUID REFERENCES players(id),   -- 接收者（关联 players.id，NULL = 公共频道）
            created_at TIMESTAMPTZ DEFAULT NOW()
        );
    END IF;

    -- 检查并添加 message_type 字段
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'messages' AND column_name = 'message_type') THEN
        ALTER TABLE messages ADD COLUMN message_type TEXT NOT NULL DEFAULT 'private';
    END IF;

    -- 检查并添加 content 字段
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'messages' AND column_name = 'content') THEN
        ALTER TABLE messages ADD COLUMN content TEXT DEFAULT '';
    END IF;

    -- 检查并添加 is_tampered 字段
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'messages' AND column_name = 'is_tampered') THEN
        ALTER TABLE messages ADD COLUMN is_tampered BOOLEAN DEFAULT FALSE;
    END IF;

    -- 检查并添加 original_content 字段
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'messages' AND column_name = 'original_content') THEN
        ALTER TABLE messages ADD COLUMN original_content TEXT;
    END IF;

    -- 检查并添加 is_read 字段
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'messages' AND column_name = 'is_read') THEN
        ALTER TABLE messages ADD COLUMN is_read BOOLEAN DEFAULT FALSE;
    END IF;

    -- 检查并添加 is_intercepted 字段
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'messages' AND column_name = 'is_intercepted') THEN
        ALTER TABLE messages ADD COLUMN is_intercepted BOOLEAN DEFAULT FALSE;
    END IF;

    -- 检查并添加 stamina_cost 字段
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'messages' AND column_name = 'stamina_cost') THEN
        ALTER TABLE messages ADD COLUMN stamina_cost INT DEFAULT 0;
    END IF;

    -- 检查并添加 attachments 字段
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'messages' AND column_name = 'attachments') THEN
        ALTER TABLE messages ADD COLUMN attachments JSONB DEFAULT '[]';
    END IF;

    -- 检查并添加 expires_at 字段
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'messages' AND column_name = 'expires_at') THEN
        ALTER TABLE messages ADD COLUMN expires_at TIMESTAMPTZ;
    END IF;

    -- 检查并添加 stage 字段
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'messages' AND column_name = 'stage') THEN
        IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'messages' AND column_name = 'ferment_stage') THEN
            ALTER TABLE messages RENAME COLUMN ferment_stage TO stage;
        ELSE
            ALTER TABLE messages ADD COLUMN stage INT DEFAULT 0;
        END IF;
    END IF;

    -- 检查并添加 updated_at 字段
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = 'messages' AND column_name = 'updated_at') THEN
        ALTER TABLE messages ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- 2. 确保反应表和状态表存在
CREATE TABLE IF NOT EXISTS message_reactions ( 
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), 
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE, 
  reactor_uid UUID REFERENCES players(id), 
  reaction_type TEXT NOT NULL,  -- 'like' / 'dislike' / 'report' / 'endorse' 
  created_at TIMESTAMPTZ DEFAULT NOW(), 
  UNIQUE(message_id, reactor_uid, reaction_type) 
); 

CREATE TABLE IF NOT EXISTS inbox_status ( 
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), 
  player_uid UUID REFERENCES players(id), 
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE, 
  is_archived BOOLEAN DEFAULT FALSE, 
  is_starred BOOLEAN DEFAULT FALSE, 
  read_at TIMESTAMPTZ, 
  UNIQUE(player_uid, message_id) 
); 

-- 3. 启用并重置 RLS
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE inbox_status ENABLE ROW LEVEL SECURITY;

-- 删除旧策略以防冲突
DROP POLICY IF EXISTS messages_private_read ON messages;
DROP POLICY IF EXISTS messages_rumor_read ON messages;
DROP POLICY IF EXISTS messages_batch_order_read ON messages;
DROP POLICY IF EXISTS messages_system_read ON messages;
DROP POLICY IF EXISTS messages_others_read ON messages;
DROP POLICY IF EXISTS messages_insert ON messages;
DROP POLICY IF EXISTS "Involved players can view messages" ON messages; -- maid_system_schema 中的旧策略

-- 使用 get_my_player_id() 辅助函数（假设已在 maid_system_schema.sql 中定义）
-- 如果没有定义，这里重新定义一个
CREATE OR REPLACE FUNCTION get_my_player_id()
RETURNS UUID AS $$
    SELECT id FROM players WHERE auth_uid = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER;

-- 4. 重新创建 RLS 策略
-- private 类型消息仅发送者和接收者可读
CREATE POLICY messages_private_read ON messages
  FOR SELECT
  USING (
    message_type = 'private' 
    AND (get_my_player_id() = sender_uid OR get_my_player_id() = receiver_uid)
  );

-- rumor 类型消息所有同局玩家可读
CREATE POLICY messages_rumor_read ON messages
  FOR SELECT
  USING (
    message_type = 'rumor'
    AND game_id IN (
      SELECT current_game_id FROM players WHERE auth_uid = auth.uid()
    )
  );

-- batch_order 类型仅管家和接收者可读
CREATE POLICY messages_batch_order_read ON messages
  FOR SELECT
  USING (
    message_type = 'batch_order'
    AND (
      get_my_player_id() = receiver_uid 
      OR EXISTS (
        SELECT 1 FROM players 
        WHERE auth_uid = auth.uid() AND role_class = 'steward'
      )
    )
  );

-- system 类型所有人可读
CREATE POLICY messages_system_read ON messages
  FOR SELECT
  USING (message_type = 'system');

-- 所有人可发信
CREATE POLICY messages_insert ON messages
  FOR INSERT
  WITH CHECK (
    sender_uid = get_my_player_id() OR sender_uid IS NULL
  );

-- inbox_status RLS
DROP POLICY IF EXISTS inbox_status_all ON inbox_status;
CREATE POLICY inbox_status_all ON inbox_status
  FOR ALL
  USING (get_my_player_id() = player_uid);

-- message_reactions RLS
DROP POLICY IF EXISTS message_reactions_all ON message_reactions;
CREATE POLICY message_reactions_all ON message_reactions
  FOR ALL
  USING (get_my_player_id() = reactor_uid);
