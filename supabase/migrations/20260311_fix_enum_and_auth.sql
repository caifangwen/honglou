-- 1. 为 maid_relation_status 枚举添加 'pending' 值
-- 使用 DO 块以防重复执行报错
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'pending' AND enumtypid = 'maid_relation_status'::regtype) THEN
        ALTER TYPE maid_relation_status ADD VALUE 'pending' BEFORE 'active';
    END IF;
END $$;

-- 2. 授权 get_email_by_username 函数给匿名用户，以便在登录前调用
GRANT EXECUTE ON FUNCTION get_email_by_username(TEXT) TO anon, authenticated;
