-- seed.sql - 测试数据
-- 重要提示: 在运行此脚本之前，请确保已先运行并成功执行了 combined_schema.sql 以创建所有必要的表。
-- 使用方法: 在 Supabase SQL Editor 中运行

-- 检查表是否存在，如果不存在则报错提示用户
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename  = 'games') THEN
        RAISE EXCEPTION '表 public.games 不存在。请先运行 combined_schema.sql 初始化数据库架构。';
    END IF;
END $$;

-- 1. 确保有一个基础游戏局 (ID 与 TreasuryUI.gd/combined_schema.sql 保持一致)
INSERT INTO public.games (id, start_timestamp, status, speed_multiplier, deficit_value)
VALUES ('00000000-0000-0000-0000-000000000001', extract(epoch from now())::bigint, 'active', 1.0, 0.0)
ON CONFLICT (id) DO UPDATE SET status = 'active';

-- 2. 确保有一个银库
INSERT INTO public.treasury (game_id, total_silver, daily_budget, public_balance, real_balance, prosperity_level, deficit_rate)
VALUES ('00000000-0000-0000-0000-000000000001', 50000, 2000, 50000, 50000, 8, 0.0)
ON CONFLICT (game_id) DO UPDATE SET 
    total_silver = EXCLUDED.total_silver,
    public_balance = EXCLUDED.public_balance,
    real_balance = EXCLUDED.real_balance;

-- 3. 创建测试玩家
-- 3.1 清理冲突的旧数据 (确保特定测试账号 UUID 可用)
-- 先删除所有引用这些玩家的外键记录

-- 删除 ledger_entries 中的记录
DELETE FROM public.ledger_entries WHERE target_id IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
) OR actor_id IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
);

-- 删除 messages 中的记录
DELETE FROM public.messages WHERE sender_uid IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
) OR receiver_uid IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
);

-- 删除 steward_accounts 中的记录
DELETE FROM public.steward_accounts WHERE steward_uid IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
);

-- 删除 maid_relationships 中的记录
DELETE FROM public.maid_relationships WHERE player_a_uid IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
) OR player_b_uid IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
);

-- 删除其他可能的外键引用表（根据需要添加）
-- 如果还有其他表引用 players，也需要在这里删除

-- 现在可以安全删除 players 表中的记录
DELETE FROM public.players WHERE auth_uid IN (
    SELECT id FROM auth.users WHERE email IN (
        'fengjie@example.com', 'baoyu@test.com', 'daiyu@test.com',
        'xiren@example.com', 'qingwen@example.com'
    )
) OR id IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
);

DELETE FROM auth.users WHERE email IN (
    'fengjie@example.com', 'baoyu@test.com', 'daiyu@test.com',
    'xiren@example.com', 'qingwen@example.com'
) OR id IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
);

-- 3.2 模拟插入 auth.users (针对 Supabase 本地环境，增加了必需字段以防插入失败)
-- 注意：在实际 Supabase 环境中，密码需要通过 auth.signup() 创建
-- 这里使用预定义的测试密码 "123456" 的哈希值
-- 使用 crypt() 函数生成密码哈希
INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token,
    email_change_token_new, email_change
)
VALUES
    ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated', 'fengjie@example.com', crypt('123456', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"name": "凤姐"}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated', 'baoyu@test.com', crypt('123456', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"name": "宝玉"}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', '33333333-3333-3333-3333-333333333333', 'authenticated', 'authenticated', 'daiyu@test.com', crypt('123456', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"name": "黛玉"}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', '44444444-4444-4444-4444-444444444444', 'authenticated', 'authenticated', 'xiren@example.com', crypt('123456', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"name": "袭人"}', now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', '55555555-5555-5555-5555-555555555555', 'authenticated', 'authenticated', 'qingwen@example.com', crypt('123456', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"name": "晴雯"}', now(), now(), '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- 3.3 关联到 public.players
-- 增加了 username 字段以支持应用内的快捷登录匹配逻辑
INSERT INTO public.players (id, auth_uid, username, display_name, character_name, role_class, current_game_id, silver, private_silver)
VALUES 
    ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'fengjie', '凤辣子', '凤姐', 'steward', '00000000-0000-0000-0000-000000000001', 100, 500),
    ('22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'baoyu', '宝二爷', '贾宝玉', 'master', '00000000-0000-0000-0000-000000000001', 50, 0),
    ('33333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'daiyu', '林姑娘', '林黛玉', 'master', '00000000-0000-0000-0000-000000000001', 30, 0),
    ('44444444-4444-4444-4444-444444444444', '44444444-4444-4444-4444-444444444444', 'xiren', '袭人姑娘', '袭人', 'servant', '00000000-0000-0000-0000-000000000001', 10, 0),
    ('55555555-5555-5555-5555-555555555555', '55555555-5555-5555-5555-555555555555', 'qingwen', '晴雯姑娘', '晴雯', 'servant', '00000000-0000-0000-0000-000000000001', 5, 0)
ON CONFLICT (auth_uid) DO UPDATE SET 
    current_game_id = EXCLUDED.current_game_id,
    username = EXCLUDED.username,
    display_name = EXCLUDED.display_name,
    character_name = EXCLUDED.character_name,
    role_class = EXCLUDED.role_class;

-- 初始化管家账本
INSERT INTO public.steward_accounts (game_id, steward_uid, private_assets, prestige)
SELECT '00000000-0000-0000-0000-000000000001', id, 500, 80 
FROM public.players 
WHERE character_name = '凤姐'
ON CONFLICT (game_id, steward_uid) DO NOTHING;
