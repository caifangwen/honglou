-- seed.sql - 测试数据
-- 使用方法: 在 Supabase SQL Editor 中运行

-- 1. 确保有一个基础游戏局 (ID 与 TreasuryUI.gd/combined_schema.sql 保持一致)
INSERT INTO public.games (id, start_timestamp, status, speed_multiplier, deficit_value)
VALUES ('00000000-0000-0000-0000-000000000001', extract(epoch from now())::bigint, 'active', 1.0, 0.0)
ON CONFLICT (id) DO UPDATE SET status = 'active';

-- 2. 确保有一个银库
INSERT INTO public.treasury (game_id, total_silver, daily_budget, public_balance, real_balance, prosperity_level, deficit_rate)
VALUES ('00000000-0000-0000-0000-000000000001', 50000, 2000, 50000, 50000, 8, 0.0)
ON CONFLICT (game_id) DO UPDATE SET total_silver = 50000;

-- 3. 创建测试玩家
-- 模拟插入 auth.users (仅限本地或有权限的环境)
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES 
    ('11111111-1111-1111-1111-111111111111', 'fengjie@example.com', '{"name": "凤姐"}'),
    ('22222222-2222-2222-2222-222222222222', 'baoyu@test.com', '{"name": "宝玉"}'),
    ('33333333-3333-3333-3333-333333333333', 'daiyu@test.com', '{"name": "黛玉"}'),
    ('44444444-4444-4444-4444-444444444444', 'xiren@example.com', '{"name": "袭人"}'),
    ('55555555-5555-5555-5555-555555555555', 'qingwen@example.com', '{"name": "晴雯"}')
ON CONFLICT (id) DO NOTHING;

-- 关联到 public.players
INSERT INTO public.players (id, auth_uid, display_name, character_name, role_class, current_game_id, silver, private_silver)
VALUES 
    (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', '凤辣子', '凤姐', 'steward', '00000000-0000-0000-0000-000000000001', 100, 500),
    (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', '宝二爷', '贾宝玉', 'master', '00000000-0000-0000-0000-000000000001', 50, 0),
    (gen_random_uuid(), '33333333-3333-3333-3333-333333333333', '林姑娘', '林黛玉', 'master', '00000000-0000-0000-0000-000000000001', 30, 0),
    (gen_random_uuid(), '44444444-4444-4444-4444-444444444444', '袭人姑娘', '袭人', 'servant', '00000000-0000-0000-0000-000000000001', 10, 0),
    (gen_random_uuid(), '55555555-5555-5555-5555-555555555555', '晴雯姑娘', '晴雯', 'servant', '00000000-0000-0000-0000-000000000001', 5, 0)
ON CONFLICT (auth_uid) DO UPDATE SET current_game_id = EXCLUDED.current_game_id;

-- 初始化管家账本
INSERT INTO public.steward_accounts (game_id, steward_uid, private_assets, prestige)
SELECT '00000000-0000-0000-0000-000000000001', id, 500, 80 
FROM public.players 
WHERE character_name = '凤姐'
ON CONFLICT (game_id, steward_uid) DO NOTHING;
