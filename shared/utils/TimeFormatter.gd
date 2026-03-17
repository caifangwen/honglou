class_name TimeFormatter

## 时间格式化工具库（静态类）

const CHINESE_NUMBERS = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二"]
const SHICHEN_NAMES = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
const XUN_NAMES = ["上旬", "中旬", "下旬"]

## 游戏时间转汉字表达
## 返回格式：「三月上旬第七日·午时」
static func to_game_date_string(unix_ts: float, start_ts: float, speed: float = 1.0) -> String:
	var game_seconds = (unix_ts - start_ts) * speed
	if game_seconds < 0: game_seconds = 0
	
	var month = int(game_seconds / 216000.0) + 1
	var xun_idx = int(fmod(game_seconds, 216000.0) / 72000.0)
	var day = int(fmod(game_seconds, 72000.0) / 7200.0) + 1
	var day_progress = fmod(game_seconds, 7200.0) / 7200.0
	
	var month_str = str(month)
	if month < CHINESE_NUMBERS.size(): month_str = CHINESE_NUMBERS[month]
	
	var day_str = str(day)
	if day < CHINESE_NUMBERS.size(): day_str = CHINESE_NUMBERS[day]
	
	return "「%s月%s第%s日·%s时」" % [month_str, get_xun_name(xun_idx), day_str, get_shichen(day_progress)]

## 倒计时转双格式字符串
## 返回格式：「约两个时辰后（现实约4小时）」
static func to_countdown_string(remaining_seconds: float, speed: float = 1.0) -> String:
	if remaining_seconds <= 0: return "立即"
	
	var game_remaining_seconds = remaining_seconds * speed
	var shichen_val = game_remaining_seconds / 600.0 # 1个时辰 = 600秒游戏时间
	
	var shichen_str = ""
	if shichen_val >= 1.0:
		shichen_str = "约%s个时辰后" % CHINESE_NUMBERS[int(shichen_val)] if int(shichen_val) < CHINESE_NUMBERS.size() else str(int(shichen_val))
	else:
		shichen_str = "片刻后"
	
	var real_h = int(remaining_seconds / 3600.0)
	var real_m = int(fmod(remaining_seconds, 3600.0) / 60.0)
	
	var real_str = ""
	if real_h > 0:
		real_str = "（现实约%d小时）" % real_h
	else:
		real_str = "（现实约%d分钟）" % real_m
		
	return "%s%s" % [shichen_str, real_str]

## 根据 0.0–1.0 进度返回十二时辰名称
static func get_shichen(day_progress: float) -> String:
	var index = int(day_progress * 12) % 12
	return SHICHEN_NAMES[index]

## 返回「上旬」「中旬」「下旬」
static func get_xun_name(xun_index: int) -> String:
	if xun_index >= 0 and xun_index < XUN_NAMES.size():
		return XUN_NAMES[xun_index]
	return "未知旬"

## 精力恢复倒计时计算
static func get_stamina_recovery_countdown(last_refresh: float, current_stamina: int, max_stamina: int, speed: float) -> Dictionary:
	var now = Time.get_unix_time_from_system()
	var elapsed = (now - last_refresh) * speed
	var recovery_interval = 7200.0 # 1点精力 = 1游戏日 = 7200秒游戏时间
	
	var pending_recoveries = int(elapsed / recovery_interval)
	var next_recovery_in = (recovery_interval - fmod(elapsed, recovery_interval)) / speed
	
	var total_needed = max_stamina - current_stamina - pending_recoveries
	if total_needed <= 0:
		return { "next_recovery_in": 0.0, "full_recovery_in": 0.0, "recoveries_pending": pending_recoveries }
	
	var full_recovery_in = (total_needed * recovery_interval - fmod(elapsed, recovery_interval)) / speed
	
	return {
		"next_recovery_in": next_recovery_in,
		"full_recovery_in": full_recovery_in,
		"recoveries_pending": pending_recoveries
	}

## 流言状态判断
static func get_rumor_stage(created_at: float, current_time: float, speed: float) -> Dictionary:
	var elapsed_game_seconds = (current_time - created_at) * speed
	var elapsed_hours = elapsed_game_seconds / 3600.0 # 游戏内小时
	
	# stage 0: 口耳相传（0–6小时游戏时间）
	# stage 1: 人尽皆知（6–12小时游戏时间）
	# stage 2: 板上钉钉（12小时后游戏时间）
	
	var stage = 0
	var stage_name = "口耳相传"
	var expires_in = 0.0
	var can_suppress = true
	
	if elapsed_hours >= 12.0:
		stage = 2
		stage_name = "板上钉钉"
		can_suppress = false
	elif elapsed_hours >= 6.0:
		stage = 1
		stage_name = "人尽皆知"
		expires_in = (12.0 * 3600.0 - elapsed_game_seconds) / speed
	else:
		stage = 0
		stage_name = "口耳相传"
		expires_in = (6.0 * 3600.0 - elapsed_game_seconds) / speed
		
	return {
		"stage": stage,
		"stage_name": stage_name,
		"expires_in": expires_in,
		"can_suppress": can_suppress
	}
