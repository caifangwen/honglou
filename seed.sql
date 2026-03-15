-- ============================================================
-- 《红楼回忆志》数据库种子数据
-- 版本：2026-03-15
-- 使用方法：在 Supabase SQL Editor 中执行
-- 注意：请先运行 schema.sql 创建表结构
-- ============================================================

-- 检查表是否存在
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'games') THEN
        RAISE EXCEPTION '表 public.games 不存在。请先运行 schema.sql 初始化数据库架构。';
    END IF;
END $$;

-- ============================================================
-- 1. 基础游戏局
-- ============================================================

INSERT INTO public.games (id, start_timestamp, status, speed_multiplier, deficit_value)
VALUES ('00000000-0000-0000-0000-000000000001', extract(epoch from now())::bigint, 'active', 1.0, 0.0)
ON CONFLICT (id) DO UPDATE SET status = 'active';

-- ============================================================
-- 2. 银库初始化
-- ============================================================

INSERT INTO public.treasury (game_id, total_silver, daily_budget, public_balance, real_balance, prosperity_level, deficit_rate)
VALUES ('00000000-0000-0000-0000-000000000001', 50000, 2000, 50000, 50000, 8, 0.0)
ON CONFLICT (game_id) DO UPDATE SET
    total_silver = EXCLUDED.total_silver,
    public_balance = EXCLUDED.public_balance,
    real_balance = EXCLUDED.real_balance;

-- ============================================================
-- 3. 清理旧测试数据
-- ============================================================

-- 删除外键引用记录
DELETE FROM public.ledger_entries WHERE target_id IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
) OR actor_id IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
);

DELETE FROM public.messages WHERE sender_uid IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
) OR receiver_uid IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
);

DELETE FROM public.steward_accounts WHERE steward_uid IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
);

DELETE FROM public.maid_relationships WHERE player_a_uid IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
) OR player_b_uid IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
);

DELETE FROM public.intel_fragments WHERE owner_uid IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
);

DELETE FROM public.eavesdrop_sessions WHERE player_uid IN (
    '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555'
);

-- 删除 players 和 auth.users
DELETE FROM public.players WHERE auth_uid IN (
    SELECT id FROM auth.users WHERE email IN (
        'fengjie@example.com', 'baoyu@test.com', 'daiyu@test.com',
        'xiren@example.com', 'qingwen@example.com'
    )
);

DELETE FROM auth.users WHERE email IN (
    'fengjie@example.com', 'baoyu@test.com', 'daiyu@test.com',
    'xiren@example.com', 'qingwen@example.com'
);

-- ============================================================
-- 4. 创建测试账号
-- ============================================================

-- 密码均为：123456
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

-- 关联到 public.players
INSERT INTO public.players (id, auth_uid, username, display_name, character_name, role_class, current_game_id, silver, private_silver, reputation)
VALUES
    ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'fengjie', '凤辣子', '凤姐', 'steward', '00000000-0000-0000-0000-000000000001', 100, 500, 80),
    ('22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'baoyu', '宝二爷', '贾宝玉', 'master', '00000000-0000-0000-0000-000000000001', 50, 0, 50),
    ('33333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'daiyu', '林姑娘', '林黛玉', 'master', '00000000-0000-0000-0000-000000000001', 30, 0, 50),
    ('44444444-4444-4444-4444-444444444444', '44444444-4444-4444-4444-444444444444', 'xiren', '袭人姑娘', '袭人', 'servant', '00000000-0000-0000-0000-000000000001', 10, 0, 50),
    ('55555555-5555-5555-5555-555555555555', '55555555-5555-5555-5555-555555555555', 'qingwen', '晴雯姑娘', '晴雯', 'servant', '00000000-0000-0000-0000-000000000001', 5, 0, 50)
ON CONFLICT (auth_uid) DO UPDATE SET
    current_game_id = EXCLUDED.current_game_id,
    username = EXCLUDED.username,
    display_name = EXCLUDED.display_name,
    character_name = EXCLUDED.character_name,
    role_class = EXCLUDED.role_class,
    silver = EXCLUDED.silver,
    private_silver = EXCLUDED.private_silver,
    reputation = EXCLUDED.reputation;

-- ============================================================
-- 5. 初始化管家账本
-- ============================================================

INSERT INTO public.steward_accounts (game_id, steward_uid, private_assets, prestige)
SELECT '00000000-0000-0000-0000-000000000001', id, 500, 80
FROM public.players
WHERE character_name = '凤姐'
ON CONFLICT (game_id, steward_uid) DO NOTHING;

-- ============================================================
-- 6. 初始化精力表
-- ============================================================

INSERT INTO public.steward_stamina (uid, current_stamina, max_stamina)
SELECT id, 6, 6 FROM public.players WHERE role_class = 'steward'
ON CONFLICT (uid) DO NOTHING;
