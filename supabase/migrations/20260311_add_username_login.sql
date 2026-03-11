-- 为 players 表增加 username 字段并支持用户名登录

-- 1. 增加 username 字段
ALTER TABLE players ADD COLUMN IF NOT EXISTS username TEXT UNIQUE;

-- 2. 创建 RPC 函数：根据用户名获取关联的 Email
-- 需要 SECURITY DEFINER 权限以访问 auth.users
CREATE OR REPLACE FUNCTION get_email_by_username(p_username TEXT)
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
