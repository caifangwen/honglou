-- # 任务：为《大观园》初始化 Supabase 数据库结构
-- ## 项目背景
-- 《大观园》是一款百人异步社交策略游戏，引擎 Godot 4，后端使用 Supabase。
-- 玩家扮演贾府各色人物，核心玩法包括：资源分配、情报交易、流言博弈、查账对抗。
-- 地图采用可漫游的 2D 像素瓦片地图，玩家物理走到地点触发对应系统。

-- ## 一、核心表结构

-- 1. players（玩家基础数据）
create table players (
  id uuid primary key default gen_random_uuid(),
  auth_uid uuid unique not null references auth.users(id),

  -- 角色扮演
  display_name text not null,
  character_name text,              -- 扮演的角色名，如"王熙凤"
  role_class text not null          -- 'steward'|'master'|'servant'|'elder'|'guest'
    check (role_class in ('steward','master','servant','elder','guest')),

  -- 当前局游戏ID
  current_game_id uuid,

  -- 通用数值
  stamina int not null default 6,
  stamina_max int not null default 6,
  stamina_refreshed_at timestamptz default now(),

  qi_shu int not null default 100,       -- 气数，上限200
  silver int not null default 0,         -- 个人私产
  face_value int not null default 50,    -- 体面值，上限100
  prestige int not null default 10,      -- 名望值（主子专用），上限200
  loyalty int not null default 50,       -- 忠诚度（丫鬟专用），上限100

  -- 状态标记
  is_disgraced bool default false,       -- 声名狼藉
  betrayal_count int default 0,         -- 背叛次数（弃主次数）

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 2. games（局级全局状态）
create table games (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'active'
    check (status in ('active','crisis','purge','ended')),

  current_day int not null default 1,
  deficit_value numeric(5,2) default 0,    -- 家族亏空值 0~100
  conflict_value numeric(5,2) default 0,   -- 家族内耗值 0~100

  started_at timestamptz default now(),
  ended_at timestamptz,

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 3. treasury（公中银库）
create table treasury (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references games(id),

  -- 明账（对外公示）vs 暗账（真实数据），两套数字
  public_balance numeric(10,2) not null default 10000,   -- 明账余额
  real_balance numeric(10,2) not null default 10000,     -- 暗账余额

  -- 最近一次月例发放状态
  last_allocation_day int default 0,

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 4. ledger_entries（账目流水，明暗两套）
create table ledger_entries (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references games(id),
  treasury_id uuid not null references treasury(id),

  ledger_type text not null
    check (ledger_type in ('public','private')),  -- 明账or暗账

  entry_type text not null
    check (entry_type in (
      'allocation',    -- 月例发放
      'deduction',     -- 克扣
      'procurement',   -- 采办
      'advance',       -- 预支
      'bribe',         -- 贿赂
      'reward'         -- 赏赐
    )),

  amount numeric(10,2) not null,
  actor_id uuid references players(id),      -- 操作者（管家）
  target_id uuid references players(id),     -- 涉及的玩家
  note text,                                 -- 备注（明账填假由头，暗账填真实原因）

  created_at timestamptz default now()
);

-- 5. actions（批条/行动队列）
create table actions (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references games(id),
  actor_id uuid not null references players(id),

  action_type text not null
    check (action_type in (
      'procure',         -- 采办物资
      'assign_task',     -- 差使分派
      'search_garden',   -- 搜检大观园
      'advance_payment', -- 预支批条
      'suppress_rumor',  -- 平息流言
      'block_info',      -- 封锁消息
      'publish_rumor',   -- 发布流言（丫鬟）
      'wiretap',         -- 挂机监听（丫鬟）
      'audit'            -- 发起查账
    )),

  stamina_cost int not null,
  target_id uuid references players(id),      -- 作用对象（可空）
  payload jsonb default '{}',                 -- 行动参数（通用扩展字段）

  status text not null default 'pending'
    check (status in ('pending','resolved','cancelled')),

  resolved_at timestamptz,
  created_at timestamptz default now()
);

-- 6. rumors（流言及发酵状态）
create table rumors (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references games(id),
  author_id uuid not null references players(id),
  target_id uuid not null references players(id),

  content text not null,
  ferment_stage int not null default 1
    check (ferment_stage in (1, 2, 3)),
  -- 1: 口耳相传（0~6h） 2: 人尽皆知（6~12h） 3: 板上钉钉（12h+）

  is_suppressed bool default false,
  suppressed_by uuid references players(id),
  suppressed_at timestamptz,

  penalty_applied bool default false,   -- 是否已结算惩罚

  -- 是否由两条情报碎片合并而来（流言嫁接）
  is_grafted bool default false,
  source_intel_ids uuid[] default '{}',

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 7. intel_fragments（情报碎片背包）
create table intel_fragments (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references games(id),
  owner_id uuid not null references players(id),     -- 当前持有者

  fragment_type text not null
    check (fragment_type in (
      'ledger_leak',    -- 账目漏洞碎片
      'private_action', -- 私人行动记录
      'gift_record',    -- 赠礼记录
      'letter',         -- 私信/情书
      'deal_record',    -- 交易记录
      'elder_favor'     -- 元老偏好情报
    )),

  content text not null,                -- 情报内容（可读文本）
  about_player_id uuid references players(id),  -- 情报涉及的玩家
  value_score int default 10,           -- 情报价值（影响出售价格）

  -- 来源
  source_location text,                 -- 获取地点（怡红院/账房等）
  acquired_via text default 'wiretap',  -- 获取方式

  is_used bool default false,
  is_sold bool default false,
  sold_to uuid references players(id),
  sold_price int,

  created_at timestamptz default now()
);

-- 8. relationships（玩家关系网络）
create table relationships (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references games(id),
  player_a uuid not null references players(id),
  player_b uuid not null references players(id),

  relation_type text not null
    check (relation_type in (
      'ally',           -- 同盟
      'rival',          -- 对手
      'confidant',      -- 亲信（计入社交资本）
      'admirer',        -- 爱慕（计入社交资本）
      'duo_wiretap',    -- 对食/私约（双人挂机）
      'betrayed'        -- 已背叛关系
    )),

  initiated_by uuid references players(id),
  is_mutual bool default false,         -- 是否双向确认

  created_at timestamptz default now(),
  updated_at timestamptz default now(),

  unique(game_id, player_a, player_b, relation_type)
);

-- 9. map_locations（地图地点状态）
create table map_locations (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references games(id),

  location_key text not null,   -- 'yihong_yuan' | 'treasury_room' | 'bridge' | 'gate' | 'grandma'
  location_name text not null,  -- 显示名称

  -- 当前正在此处挂机监听的玩家（最多2人，对食机制）
  wiretapping_players uuid[] default '{}',

  -- 该地点今日是否触发过稀有情报
  rare_intel_triggered bool default false,
  rare_intel_reset_at timestamptz,

  created_at timestamptz default now(),
  updated_at timestamptz default now(),

  unique(game_id, location_key)
);

-- 10. events（突发事件日志）
create table events (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references games(id),

  event_type text not null
    check (event_type in (
      'yuan_fei_visit',   -- 元妃省亲
      'funeral',          -- 大出殡
      'garden_raid',      -- 抄检大观园
      'inspection',       -- 贾政大检查
      'liu_laolao',       -- 刘姥姥进大观园
      'financial_crisis', -- 财政危机
      'purge'             -- 抄家清算
    )),

  status text default 'active'
    check (status in ('active','resolving','ended')),

  deadline_at timestamptz,              -- 玩家响应截止时间
  payload jsonb default '{}',           -- 事件参数（如省亲预算金额）

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ## 二、辅助设施
-- 自动更新 updated_at 的触发器（所有表通用）
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_players_updated
  before update on players
  for each row execute function update_updated_at();

create trigger trg_games_updated
  before update on games
  for each row execute function update_updated_at();

create trigger trg_treasury_updated
  before update on treasury
  for each row execute function update_updated_at();

create trigger trg_rumors_updated
  before update on rumors
  for each row execute function update_updated_at();

create trigger trg_relationships_updated
  before update on relationships
  for each row execute function update_updated_at();

create trigger trg_map_locations_updated
  before update on map_locations
  for each row execute function update_updated_at();

create trigger trg_events_updated
  before update on events
  for each row execute function update_updated_at();

-- Row Level Security（全开放）
alter table players enable row level security;
alter table games enable row level security;
alter table treasury enable row level security;
alter table ledger_entries enable row level security;
alter table actions enable row level security;
alter table rumors enable row level security;
alter table intel_fragments enable row level security;
alter table relationships enable row level security;
alter table map_locations enable row level security;
alter table events enable row level security;

create policy "dev_open" on players for all using (true);
create policy "dev_open" on games for all using (true);
create policy "dev_open" on treasury for all using (true);
create policy "dev_open" on ledger_entries for all using (true);
create policy "dev_open" on actions for all using (true);
create policy "dev_open" on rumors for all using (true);
create policy "dev_open" on intel_fragments for all using (true);
create policy "dev_open" on relationships for all using (true);
create policy "dev_open" on map_locations for all using (true);
create policy "dev_open" on events for all using (true);

-- ## 三、假数据
insert into games (id, status, current_day, deficit_value, conflict_value)
values ('00000000-0000-0000-0000-000000000001', 'active', 1, 12.5, 8.0);

insert into treasury (game_id, public_balance, real_balance)
values ('00000000-0000-0000-0000-000000000001', 10000, 8500);

insert into map_locations (game_id, location_key, location_name) values
  ('00000000-0000-0000-0000-000000000001', 'yihong_yuan', '怡红院后窗'),
  ('00000000-0000-0000-0000-000000000001', 'treasury_room', '管家后账房'),
  ('00000000-0000-0000-0000-000000000001', 'bridge', '蜂腰桥'),
  ('00000000-0000-0000-0000-000000000001', 'gate', '荣国府大门'),
  ('00000000-0000-0000-0000-000000000001', 'grandma', '贾母处');
