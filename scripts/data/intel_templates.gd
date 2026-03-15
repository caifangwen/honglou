extends Node

# IntelTemplates.gd - 情报内容模板
# 使用变量替换生成真实内容，变量来源为玩家行动日志（actions 表）

var templates = {
	"account_leak": [
		"{source_name}在{date}的账目中，{item}实际花费{real_amount}两，明账记录{fake_amount}两，差额{diff}两不知去向。",
		"管家批条显示，{source_name}采办{item}一批，截留约{percent}%未入公库。",
		"账房先生私下议论，{source_name}经手的{item}款项有蹊跷，少了{missing_amount}两。"
	],
	"gift_record": [
		"{source_name}于{date}秘密赠送{receiver_name}{gift_item}一件，并未登记礼单。",
		"{source_name}托{carrier_name}带话，私下赏赐{receiver_name}{silver}两。",
		"有人瞧见{source_name}把一包贵重物品塞给了{receiver_name}，像是{gift_item}。"
	],
	"private_action": [
		"{source_name}在{time}悄悄去了{location}，停留约{duration}，随后{action}。",
		"小丫鬟撞见{source_name}在{location}与人密谈，话题涉及{topic}。",
		"夜深人静时，{source_name}独自一人在{location}徘徊，似乎在等什么人。"
	],
	"visitor_info": [
		"{date}，来客{visitor_name}携礼单拜访，内含{items}，由{receiver_name}接待。",
		"门外来了位贵客{visitor_name}，带来{items}，说是给{receiver_name}的贺礼。",
		"有远客{visitor_name}到访，指名要见{receiver_name}，还带了封密信。"
	],
	"elder_favor": [
		"贾母近日频频夸赞{target_name}，赏赐{gift}，似有重用之意。",
		"老太太在宴会上特意让{target_name}坐在身边，还赏了{gift}。",
		"听说贾母私下对{target_name}说，日后要委以重任。"
	]
}

# 格式化情报内容
func format_intel(type: String, data: Dictionary) -> String:
	if not templates.has(type):
		return "听到了些模糊的信息，似乎与{type}有关。".format({"type": type})

	var type_templates = templates[type]
	var template = type_templates[randi() % type_templates.size()]

	# 使用 Godot 的 String.format 进行替换
	# 注意：data 中的 key 必须与模板中的 {key} 一一对应
	return template.format(data)

# 生成备用情报（当 actions 表为空时）
func generate_fallback_intel(type: String, scene_key: String) -> String:
	var fallbacks = {
		"account_leak": [
			"听说管家最近账目有些问题，但具体说不清楚。",
			"有人在议论账房里的数字对不上。",
			"账房先生神色慌张，似乎在掩盖什么。"
		],
		"gift_record": [
			"瞧见有人偷偷递了个包裹进去，不知是什么物件。",
			"听说哪位姑娘私下收了份厚礼。",
			"有人看见一个小盒子被送到了某处。"
		],
		"private_action": [
			"瞧见个人影匆匆往那边去了，没看清是谁。",
			"听见两人在角落里低语，听不真切。",
			"有人鬼鬼祟祟地往偏僻处去了。"
		],
		"visitor_info": [
			"门外来了个生面孔，放下东西就走了。",
			"听说有远客来访，带了稀罕物件。",
			"门房说今天有贵客到访，但没看清是谁。"
		],
		"elder_favor": [
			"老太太今儿个心情好，夸了两个人。",
			"听说老太太对某个丫鬟颇为满意。",
			"贾母房里的丫鬟说，老太太最近常提起某个人。"
		]
	}
	
	var type_fallbacks = fallbacks.get(type, ["听到了些闲谈，没什么特别的。"])
	return type_fallbacks[randi() % type_fallbacks.size()]
