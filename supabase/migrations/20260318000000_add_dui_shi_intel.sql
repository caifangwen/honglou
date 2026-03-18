-- 20260318000000_add_dui_shi_intel.sql
-- 添加对食情报类型及相关场景

-- 1. 向 intel_type 枚举添加 'dui_shi'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'dui_shi' AND enumtypid = 'intel_type'::regtype) THEN
        ALTER TYPE intel_type ADD VALUE 'dui_shi';
    END IF;
END $$;

-- 2. 向 scene_location 枚举添加新场景
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'remote_rockery' AND enumtypid = 'scene_location'::regtype) THEN
        ALTER TYPE scene_location ADD VALUE 'remote_rockery';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'empty_room' AND enumtypid = 'scene_location'::regtype) THEN
        ALTER TYPE scene_location ADD VALUE 'empty_room';
    END IF;
END $$;

-- 3. 更新 intel_fragments 表的约束（如果存在）
-- intel_fragments.intel_type 已经使用了 intel_type 枚举，不需要额外操作
