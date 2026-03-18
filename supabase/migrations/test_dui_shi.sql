-- 对食功能测试脚本
-- 用于验证对食关系的基本功能

-- 1. 创建测试游戏
INSERT INTO games (id, start_timestamp, status)
VALUES ('11111111-1111-1111-1111-111111111111', 1234567890, 'active')
ON CONFLICT (id) DO NOTHING;

-- 2. 创建测试玩家（丫鬟阶层）
INSERT INTO players (id, auth_uid, display_name, character_name, role_class, current_game_id, stamina, face_value)
VALUES 
    ('22222222-2222-2222-2222-222222222221', '11111111-1111-1111-1111-111111111111', '测试丫鬟 A', '测试丫鬟 A', 'servant', '11111111-1111-1111-1111-111111111111', 8, 100),
    ('22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', '测试丫鬟 B', '测试丫鬟 B', 'servant', '11111111-1111-1111-1111-111111111111', 8, 100)
ON CONFLICT (id) DO NOTHING;

-- 3. 发起对食申请（player_a 向 player_b 发起）
INSERT INTO maid_relationships (game_id, player_a_uid, player_b_uid, relation_type, status, initiated_by)
VALUES 
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222221', '22222222-2222-2222-2222-222222222222', 'dui_shi', 'pending', '22222222-2222-2222-2222-222222222221')
ON CONFLICT (game_id, player_a_uid, player_b_uid, relation_type) DO NOTHING;

-- 4. 查询待确认的申请
SELECT 
    r.id,
    pa.character_name AS player_a_name,
    pb.character_name AS player_b_name,
    r.relation_type,
    r.status,
    r.created_at
FROM maid_relationships r
JOIN players pa ON r.player_a_uid = pa.id
JOIN players pb ON r.player_b_uid = pb.id
WHERE r.status = 'pending';

-- 5. 接受申请（更新状态为 active）
UPDATE maid_relationships 
SET status = 'active', formed_at = now()
WHERE player_a_uid = '22222222-2222-2222-2222-222222222221'
  AND player_b_uid = '22222222-2222-2222-2222-222222222222'
  AND status = 'pending';

-- 6. 查询当前活跃的对食关系
SELECT 
    r.id,
    pa.character_name AS player_a_name,
    pb.character_name AS player_b_name,
    r.relation_type,
    r.status,
    r.formed_at,
    r.shared_intel_ids
FROM maid_relationships r
JOIN players pa ON r.player_a_uid = pa.id
JOIN players pb ON r.player_b_uid = pb.id
WHERE r.status = 'active';

-- 7. 模拟共享情报（添加情报 ID 到共享列表）
UPDATE maid_relationships 
SET shared_intel_ids = array_append(shared_intel_ids, '33333333-3333-3333-3333-333333333333')
WHERE player_a_uid = '22222222-2222-2222-2222-222222222221'
  AND player_b_uid = '22222222-2222-2222-2222-222222222222';

-- 8. 验证共享情报已添加
SELECT 
    pa.character_name AS player_a_name,
    pb.character_name AS player_b_name,
    r.shared_intel_ids
FROM maid_relationships r
JOIN players pa ON r.player_a_uid = pa.id
JOIN players pb ON r.player_b_uid = pb.id
WHERE r.status = 'active';

-- 9. 清理测试数据
DELETE FROM maid_relationships WHERE game_id = '11111111-1111-1111-1111-111111111111';
DELETE FROM players WHERE current_game_id = '11111111-1111-1111-1111-111111111111';
DELETE FROM games WHERE id = '11111111-1111-1111-1111-111111111111';
