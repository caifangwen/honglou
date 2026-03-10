## 所有数值常量集中在此，禁止在其他地方写魔法数字

const TILE := {
	"SIZE": 16,          # 单个瓦片像素尺寸（世界坐标单位）
	"SCALE": 3           # 渲染放大倍数（16×3 = 48px 屏幕像素）
}

const MAP := {
	"COLS": 20,          # 地图列数（瓦片数）
	"ROWS": 15,          # 地图行数（瓦片数）
	"LAYER_BG": 0,       # 背景层索引
	"LAYER_DECO": 1,     # 装饰层索引（可穿越）
	"LAYER_SOLID": 2,    # 碰撞层索引（实体阻挡）
	"LAYER_ABOVE": 3     # 角色上方层（覆盖渲染）
}

const PLAYER := {
	"WIDTH": 16,             # 碰撞箱宽
	"HEIGHT": 16,            # 碰撞箱高
	"SPEED": 80.0,           # 移动速度（像素/秒）
	"SPRITE_COLS": 4,        # 精灵表每行帧数
	"ANIM_FPS": 8.0,         # 动画基础帧率
	"HITBOX_OFFSET_X": 0.0,  # 碰撞箱相对精灵的偏移
	"HITBOX_OFFSET_Y": 0.0
}

const CAMERA := {
	"LERP": 0.1,         # 摄像机跟随缓动系数
	"DEADZONE_X": 60.0,  # 水平死区半径（px）
	"DEADZONE_Y": 40.0   # 垂直死区半径（px）
}

const COLLISION := {
	"SOLID_TILE_MIN": 1,   # 固体瓦片 ID 起始值（含）
	"SOLID_TILE_MAX": 63   # 固体瓦片 ID 结束值（含）
	# ID 0 = 空气（无碰撞），ID >= 64 = 特殊瓦片
}

const SPECIAL_TILES := {
	64: "LADDER",
	65: "WATER",
	66: "DAMAGE",
	67: "EXIT_NORTH",
	68: "EXIT_SOUTH",
	69: "EXIT_EAST",
	70: "EXIT_WEST"
}

