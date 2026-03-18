-- 20260319_add_dui_shi_fields.sql
-- 添加对食关系所需字段

-- 添加 formed_at 字段（记录关系建立时间）
ALTER TABLE public.maid_relationships 
ADD COLUMN IF NOT EXISTS formed_at timestamptz;

-- 添加 shared_intel_ids 字段（共享情报 ID 列表）
ALTER TABLE public.maid_relationships 
ADD COLUMN IF NOT EXISTS shared_intel_ids uuid[] DEFAULT '{}';

-- 添加 betrayer_uid 字段（背叛者 ID）
ALTER TABLE public.maid_relationships 
ADD COLUMN IF NOT EXISTS betrayer_uid uuid REFERENCES public.players(id);

-- 添加注释
COMMENT ON COLUMN public.maid_relationships.formed_at IS '关系建立时间';
COMMENT ON COLUMN public.maid_relationships.shared_intel_ids IS '共享情报 ID 列表';
COMMENT ON COLUMN public.maid_relationships.betrayer_uid IS '背叛者 ID';
