-- ============================================================
-- 《红楼回忆志》测试角色快速导入脚本
-- 版本：2026-03-19
-- 使用方法：在 Supabase SQL Editor 中直接执行
-- ============================================================

-- 检查表是否存在
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'players') THEN
        RAISE EXCEPTION '表 public.players 不存在。请先运行 schema.sql 初始化数据库架构。';
    END IF;
END $$;

-- 清理旧测试数据
DELETE FROM public.players WHERE username IN (
    'fengjie', 'pingr', 'baoyu', 'daiyu', 'baochai', 
    'yingchun', 'tanchun', 'xichun', 'xiren', 'qingwen',
    'yuanyang', 'zijuan', 'mili', 'mingyan', 'xingr'
);

-- 插入测试角色
INSERT INTO public.players (id, auth_uid, username, display_name, character_name, role_class, current_game_id, silver, private_silver, reputation, stamina, stamina_max, face_value, prestige, loyalty)
VALUES
    -- 管家（2 人）
    ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'fengjie', '凤辣子', '王熙凤', 'steward', '00000000-0000-0000-0000-000000000001', 100, 500, 80, 6, 6, 80, 80, 50),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'pingr', '平儿姑娘', '平儿', 'steward', '00000000-0000-0000-0000-000000000001', 15, 200, 55, 6, 6, 60, 55, 75),
    
    -- 主子（6 人）
    ('22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'baoyu', '宝二爷', '贾宝玉', 'master', '00000000-0000-0000-0000-000000000001', 50, 0, 50, 6, 6, 70, 60, 50),
    ('33333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'daiyu', '林姑娘', '林黛玉', 'master', '00000000-0000-0000-0000-000000000001', 30, 0, 50, 6, 6, 60, 50, 50),
    ('66666666-6666-6666-6666-666666666666', '66666666-6666-6666-6666-666666666666', 'baochai', '宝姑娘', '薛宝钗', 'master', '00000000-0000-0000-0000-000000000001', 40, 0, 50, 6, 6, 65, 55, 50),
    ('77777777-7777-7777-7777-777777777777', '77777777-7777-7777-7777-777777777777', 'yingchun', '二姑娘', '贾迎春', 'master', '00000000-0000-0000-0000-000000000001', 25, 0, 45, 6, 6, 50, 45, 50),
    ('88888888-8888-8888-8888-888888888888', '88888888-8888-8888-8888-888888888888', 'tanchun', '三姑娘', '贾探春', 'master', '00000000-0000-0000-0000-000000000001', 35, 0, 50, 6, 6, 60, 50, 50),
    ('99999999-9999-9999-9999-999999999999', '99999999-9999-9999-9999-999999999999', 'xichun', '四姑娘', '贾惜春', 'master', '00000000-0000-0000-0000-000000000001', 20, 0, 45, 6, 6, 50, 45, 50),
    
    -- 丫鬟（5 人）
    ('44444444-4444-4444-4444-444444444444', '44444444-4444-4444-4444-444444444444', 'xiren', '袭人姑娘', '袭人', 'servant', '00000000-0000-0000-0000-000000000001', 10, 0, 50, 6, 6, 55, 50, 70),
    ('55555555-5555-5555-5555-555555555555', '55555555-5555-5555-5555-555555555555', 'qingwen', '晴雯姑娘', '晴雯', 'servant', '00000000-0000-0000-0000-000000000001', 5, 0, 50, 6, 6, 60, 50, 60),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'yuanyang', '鸳鸯姑娘', '鸳鸯', 'servant', '00000000-0000-0000-0000-000000000001', 20, 0, 60, 6, 6, 65, 60, 80),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'zijuan', '紫鹃姑娘', '紫鹃', 'servant', '00000000-0000-0000-0000-000000000001', 8, 0, 50, 6, 6, 55, 50, 65),
    ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'mili', '麝月姑娘', '麝月', 'servant', '00000000-0000-0000-0000-000000000001', 7, 0, 48, 6, 6, 52, 48, 62),
    
    -- 小厮（2 人）
    ('11111110-1111-1111-1111-111111111111', '11111110-1111-1111-1111-111111111111', 'mingyan', '茗烟', '茗烟', 'servant', '00000000-0000-0000-0000-000000000001', 8, 0, 45, 6, 6, 50, 45, 55),
    ('33333330-3333-3333-3333-333333333333', '33333330-3333-3333-3333-333333333333', 'xingr', '兴儿', '兴儿', 'servant', '00000000-0000-0000-0000-000000000001', 5, 0, 40, 6, 6, 45, 40, 48)
ON CONFLICT (auth_uid) DO UPDATE SET
    current_game_id = EXCLUDED.current_game_id,
    display_name = EXCLUDED.display_name,
    character_name = EXCLUDED.character_name,
    role_class = EXCLUDED.role_class,
    silver = EXCLUDED.silver,
    private_silver = EXCLUDED.private_silver,
    reputation = EXCLUDED.reputation,
    stamina = EXCLUDED.stamina,
    stamina_max = EXCLUDED.stamina_max,
    face_value = EXCLUDED.face_value,
    prestige = EXCLUDED.prestige,
    loyalty = EXCLUDED.loyalty,
    updated_at = now();

-- 初始化管家账本（如果不存在）
INSERT INTO public.steward_accounts (game_id, steward_uid, private_assets, prestige)
SELECT '00000000-0000-0000-0000-000000000001', id, 
    CASE 
        WHEN character_name = '王熙凤' THEN 500
        WHEN character_name = '平儿' THEN 200
        ELSE 100
    END,
    80
FROM public.players
WHERE role_class = 'steward'
ON CONFLICT (game_id, steward_uid) DO NOTHING;

-- 显示导入结果
SELECT character_name, role_class, silver, reputation FROM public.players 
WHERE username IN (
    'fengjie', 'pingr', 'baoyu', 'daiyu', 'baochai', 
    'yingchun', 'tanchun', 'xichun', 'xiren', 'qingwen',
    'yuanyang', 'zijuan', 'mili', 'mingyan', 'xingr'
)
ORDER BY 
    CASE role_class 
        WHEN 'steward' THEN 1 
        WHEN 'master' THEN 2 
        WHEN 'servant' THEN 3 
        ELSE 4 
    END,
    character_name;
