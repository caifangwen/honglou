-- ============================================================
-- 本地开发环境权限设置
-- 用于 pgREST 匿名访问
-- 使用方法：docker exec -i honglou_local_db psql -U postgres -d honglou < local_dev_permissions.sql
-- ============================================================

-- 创建 anon 角色（如果不存在）
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
END $$;

-- 授予 public schema 的所有表的读取和写入权限
GRANT USAGE ON SCHEMA public TO anon;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
GRANT INSERT ON ALL TABLES IN SCHEMA public TO anon;
GRANT UPDATE ON ALL TABLES IN SCHEMA public TO anon;
GRANT DELETE ON ALL TABLES IN SCHEMA public TO anon;

-- 授予函数的执行权限
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon;

-- 授予序列的使用权限（如果有自增字段）
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon;

-- 设置默认权限（新创建的表也会自动授权）
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO anon;

-- 验证权限
SELECT grantee, table_name, privilege_type 
FROM information_schema.table_privileges 
WHERE grantee = 'anon' 
LIMIT 10;
