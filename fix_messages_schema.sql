-- ============================================================
-- 修复 messages 表结构
-- 添加寄信功能所需的字段
-- 使用方法：docker exec -i honglou_local_db psql -U postgres -d honglou < fix_messages_schema.sql
-- ============================================================

-- 添加 message_type 字段
DO $$ BEGIN
    ALTER TABLE public.messages ADD COLUMN message_type text NOT NULL DEFAULT 'private'
    CHECK (message_type IN ('private', 'rumor', 'batch_order', 'system', 'petition', 'accusation'));
EXCEPTION WHEN duplicate_column THEN RAISE NOTICE 'column message_type already exists'; END $$;

-- 添加 attachments 字段（JSONB 类型，用于存储情报碎片等附件）
DO $$ BEGIN
    ALTER TABLE public.messages ADD COLUMN attachments jsonb DEFAULT '[]'::jsonb;
EXCEPTION WHEN duplicate_column THEN RAISE NOTICE 'column attachments already exists'; END $$;

-- 添加 stamina_cost 字段
DO $$ BEGIN
    ALTER TABLE public.messages ADD COLUMN stamina_cost int NOT NULL DEFAULT 1;
EXCEPTION WHEN duplicate_column THEN RAISE NOTICE 'column stamina_cost already exists'; END $$;

-- 添加 is_tampered 字段（丫鬟传话篡改标记）
DO $$ BEGIN
    ALTER TABLE public.messages ADD COLUMN is_tampered boolean DEFAULT false;
EXCEPTION WHEN duplicate_column THEN RAISE NOTICE 'column is_tampered already exists'; END $$;

-- 添加 original_content 字段（被篡改前的原始内容）
DO $$ BEGIN
    ALTER TABLE public.messages ADD COLUMN original_content text;
EXCEPTION WHEN duplicate_column THEN RAISE NOTICE 'column original_content already exists'; END $$;

-- 添加 is_intercepted 字段（丫鬟截留标记）
DO $$ BEGIN
    ALTER TABLE public.messages ADD COLUMN is_intercepted boolean DEFAULT false;
EXCEPTION WHEN duplicate_column THEN RAISE NOTICE 'column is_intercepted already exists'; END $$;

-- 添加 stage 字段（流言发酵阶段）
DO $$ BEGIN
    ALTER TABLE public.messages ADD COLUMN stage int NOT NULL DEFAULT 0;
EXCEPTION WHEN duplicate_column THEN RAISE NOTICE 'column stage already exists'; END $$;

-- 添加 expires_at 字段（过期时间）
DO $$ BEGIN
    ALTER TABLE public.messages ADD COLUMN expires_at timestamptz;
EXCEPTION WHEN duplicate_column THEN RAISE NOTICE 'column expires_at already exists'; END $$;

-- 添加索引以提高查询性能
CREATE INDEX IF NOT EXISTS idx_messages_game_receiver ON public.messages(game_id, receiver_uid);
CREATE INDEX IF NOT EXISTS idx_messages_type ON public.messages(message_type);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON public.messages(sender_uid);

-- 添加注释
COMMENT ON COLUMN public.messages.message_type IS '消息类型：private, rumor, batch_order, system, petition, accusation';
COMMENT ON COLUMN public.messages.attachments IS '附件列表，如情报碎片';
COMMENT ON COLUMN public.messages.stamina_cost IS '精力消耗';
COMMENT ON COLUMN public.messages.is_tampered IS '是否被丫鬟篡改';
COMMENT ON COLUMN public.messages.original_content IS '原始内容（被篡改前）';
COMMENT ON COLUMN public.messages.is_intercepted IS '是否被丫鬟截留';
COMMENT ON COLUMN public.messages.stage IS '流言发酵阶段：0=初期，1=发酵中，2=已成实质';
COMMENT ON COLUMN public.messages.expires_at IS '过期时间（流言专用）';

-- 验证表结构
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'messages'
ORDER BY ordinal_position;
