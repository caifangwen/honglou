extends Node

# 情报内容模板
# 使用变量替换生成真实内容，变量来源为玩家行动日志（actions 表）

var templates = {
	"account_leak": [
		"{source_name}在{date}的账目中，{item}实际花费{real_amount}两，明账记录{fake_amount}两，差额{diff}两不知去向。",
		"管家批条显示，{source_name}采办{item}一批，截留约{percent}%未入公库。"
	],
	"gift_record": [
		"{source_name}于{date}秘密赠送{receiver_name}{gift_item}一件，并未登记礼单。",
		"{source_name}托{carrier_name}带话，私下赏赐{receiver_name}{silver}两。"
	],
	"private_action": [
		"{source_name}在{time}悄悄去了{location}，停留约{duration}，随后{action}。"
	],
	"visitor_info": [
		"{date}，来客{visitor_name}携礼单拜访，内含{items}，由{receiver_name}接待。"
	],
	"elder_favor": [
		"贾母近日频频夸赞{target_name}，赏赐{gift}，似有重用之意。"
	]
}

# 格式化情报内容
func format_intel(type: String, data: Dictionary) -> String:
	if not templates.has(type):
		return "搜集到一段模糊的信息，似乎与{type}有关。".format({"type": type})
	
	var type_templates = templates[type]
	var template = type_templates[randi() % type_templates.size()]
	
	# 使用 Godot 的 String.format 进行替换
	# 注意：data 中的 key 必须与模板中的 {key} 一一对应
	return template.format(data)
