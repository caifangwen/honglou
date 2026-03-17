extends VBoxContainer

# RelationshipPanel.gd
# 嵌入在角色信息页中的关系管理面板

@onready var status_label = $current_relation_panel/relation_status_label
@onready var betray_btn = $current_relation_panel/betray_btn
@onready var loyalty_bar = $current_relation_panel/loyalty_to_master_bar
@onready var requests_list = $incoming_requests_panel/requests_list
@onready var send_request_btn = $send_request_btn

var current_relationship: Dictionary = {}

func _ready() -> void:
    _refresh_ui()
    # 监听关系变化信号
    EventBus.relation_changed.connect(func(_a, _b, _type): _refresh_ui())

func _refresh_ui() -> void:
    # 1. 获取当前关系
    current_relationship = await RelationshipManager.get_current_relationship(PlayerState.uid)
    
    if current_relationship.is_empty():
        status_label.text = "当前对食/私约：暂无"
        betray_btn.visible = false
    else:
        var partner_name = ""
        if current_relationship.get("player_a_uid") == PlayerState.uid:
            partner_name = current_relationship.get("player_b", {}).get("character_name", "未知")
        else:
            partner_name = current_relationship.get("player_a", {}).get("character_name", "未知")
            
        var rel_type_str = "对食" if current_relationship["relation_type"] == "dui_shi" else "私约"
        status_label.text = "当前%s：%s" % [rel_type_str, partner_name]
        betray_btn.visible = true
        
    # 2. 更新忠诚度进度条
    loyalty_bar.value = PlayerState.loyalty
    
    # 3. 加载待确认申请
    _load_pending_requests()

func _load_pending_requests() -> void:
    # 清空旧列表
    for child in requests_list.get_children():
        child.queue_free()
        
    var requests = await RelationshipManager.get_pending_requests(PlayerState.uid)
    for req in requests:
        var hbox = HBoxContainer.new()
        var name_label = Label.new()
        var sender_name = req.get("player_a", {}).get("character_name", "未知")
        var type_str = "对食" if req["relation_type"] == "dui_shi" else "私约"
        name_label.text = "[%s] 发来的%s申请" % [sender_name, type_str]
        hbox.add_child(name_label)
        
        var accept_btn = Button.new()
        accept_btn.text = "接受"
        accept_btn.pressed.connect(func(): _on_accept_pressed(req["id"]))
        hbox.add_child(accept_btn)
        
        requests_list.add_child(hbox)

func _on_accept_pressed(rel_id: String) -> void:
    var success = await RelationshipManager.accept_relation_request(rel_id)
    if success:
        _refresh_ui()

func _on_send_request_btn_pressed() -> void:
    # 这里通常会弹出一个选择框让玩家选择目标，或者是从当前场景玩家列表中选择
    # 简化实现：这里仅模拟逻辑
    # RelationshipManager.send_relation_request(PlayerState.uid, target_uid, "dui_shi")
    pass

func _on_betray_btn_pressed() -> void:
    # 弹出背叛确认弹窗
    var popup = ConfirmationDialog.new()
    popup.title = "警告"
    popup.dialog_text = "背叛后，搭档将获得你们共同收集的所有情报副本。确认背叛？"
    
    var line_edit = LineEdit.new()
    line_edit.placeholder_text = "输入 '我已知晓后果' 后确认"
    popup.add_child(line_edit)
    
    popup.get_ok_button().disabled = true
    line_edit.text_changed.connect(func(new_text):
        popup.get_ok_button().disabled = (new_text != "我已知晓后果")
    )
    
    popup.confirmed.connect(func():
        if not current_relationship.is_empty():
            await RelationshipManager.betray_partner(current_relationship["id"], PlayerState.uid)
            _refresh_ui()
    )
    
    add_child(popup)
    popup.popup_centered()
