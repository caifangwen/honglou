extends Control

# RelationshipPanel.gd
# 关系管理面板（可独立场景加载）

@onready var status_label = $CenterContainer/VBoxContainer/current_relation_panel/relation_status_label
@onready var betray_btn = $CenterContainer/VBoxContainer/current_relation_panel/betray_btn
@onready var loyalty_bar = $CenterContainer/VBoxContainer/current_relation_panel/loyalty_to_master_bar
@onready var requests_list = $CenterContainer/VBoxContainer/incoming_requests_panel/requests_list
@onready var send_request_btn = $CenterContainer/VBoxContainer/send_request_btn

var current_relationship: Dictionary = {}

func _ready() -> void:
    print("[RelationshipPanel] _ready() called")
    _refresh_ui()
    # 监听关系变化信号
    EventBus.relation_changed.connect(func(_a, _b, _type): _refresh_ui())

func _on_back_btn_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/main/Hub.tscn")

func _refresh_ui() -> void:
    print("[RelationshipPanel] _refresh_ui() called")
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
        var shared_intel_count = current_relationship.get("shared_intel_ids", []).size()
        status_label.text = "当前%s：%s（共享情报：%d 条）" % [rel_type_str, partner_name, shared_intel_count]
        betray_btn.visible = true

    # 2. 更新忠诚度进度条
    loyalty_bar.value = PlayerState.loyalty

    # 3. 加载待确认申请
    _load_pending_requests()

func _load_pending_requests() -> void:
    print("[RelationshipPanel] _load_pending_requests() called")
    print("[RelationshipPanel] Current PlayerState.uid: ", PlayerState.uid)
    # 清空旧列表
    for child in requests_list.get_children():
        child.queue_free()

    var requests = await RelationshipManager.get_pending_requests(PlayerState.uid)
    print("[RelationshipPanel] Pending requests count: ", requests.size())
    print("[RelationshipPanel] Pending requests data: ", requests)
    
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
    # 使用 PopupPanel 手动创建对话框，确保按钮显示
    var popup = PopupPanel.new()
    popup.title = "发起对食/私约申请"
    popup.size = Vector2(450, 550)
    popup.exclusive = true

    # 主容器
    var main_vbox = VBoxContainer.new()
    main_vbox.add_theme_constant_override("separation", 10)
    main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
    popup.add_child(main_vbox)

    # 标题
    var title_label = Label.new()
    title_label.text = "发起对食/私约申请"
    title_label.add_theme_font_size_override("font_size", 20)
    main_vbox.add_child(title_label)

    # 类型选择
    var type_hbox = HBoxContainer.new()
    var type_label = Label.new()
    type_label.text = "关系类型："
    type_label.custom_minimum_size = Vector2(80, 0)

    var type_option = OptionButton.new()
    type_option.add_item("对食", 0)
    type_option.add_item("私约", 1)
    type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    type_hbox.add_child(type_label)
    type_hbox.add_child(type_option)
    main_vbox.add_child(type_hbox)

    # 目标选择
    var target_label = Label.new()
    target_label.text = "选择目标（仅限丫鬟/小厮）："
    main_vbox.add_child(target_label)

    var target_option = OptionButton.new()
    target_option.add_item("请选择目标...", 0)
    target_option.set_item_metadata(0, "")
    target_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    main_vbox.add_child(target_option)

    # 加载玩家列表
    await _load_players_for_selection(target_option)

    # 说明文字
    var hint_label = Label.new()
    hint_label.text = "说明：对食是较为正式的关系，私约则较为随意。双方都必须是丫鬟或小厮阶层。"
    hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
    hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
    main_vbox.add_child(hint_label)

    # 底部按钮区域
    var button_hbox = HBoxContainer.new()
    button_hbox.add_theme_constant_override("separation", 10)
    button_hbox.add_theme_constant_override("margin_top", 20)
    main_vbox.add_child(button_hbox)

    # 取消按钮
    var cancel_btn = Button.new()
    cancel_btn.text = "取消"
    cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cancel_btn.pressed.connect(popup.queue_free)
    button_hbox.add_child(cancel_btn)

    # 确认按钮
    var confirm_btn = Button.new()
    confirm_btn.text = "确认发送"
    confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    confirm_btn.pressed.connect(func():
        var selected_type_index = type_option.selected
        var relation_type = "dui_shi" if selected_type_index == 0 else "si_yue"
        var target_uid = target_option.get_item_metadata(target_option.selected)

        if not target_uid or target_uid == "":
            EventBus.show_notification.emit("请选择目标角色")
            return

        if target_uid == PlayerState.uid:
            EventBus.show_notification.emit("不能选择自己")
            return

        # 发送申请
        RelationshipManager.send_relation_request(PlayerState.uid, target_uid, relation_type)
        popup.queue_free()
    )
    button_hbox.add_child(confirm_btn)

    add_child(popup)
    popup.popup_centered()

func _load_players_for_selection(target_option: OptionButton) -> void:
    # 获取当前游戏中的所有玩家
    var game_id = PlayerState.current_game_id
    if game_id == "":
        EventBus.show_notification.emit("当前未在游戏局中")
        return

    var res = await SupabaseManager.db_get("/rest/v1/players?current_game_id=eq.%s&select=id,character_name,role_class" % game_id)
    if res["code"] != 200:
        EventBus.show_notification.emit("加载玩家列表失败")
        return

    for player in res["data"]:
        # 只显示丫鬟/小厮阶层，且不显示自己
        if player["role_class"] == "servant" and player["id"] != PlayerState.uid:
            target_option.add_item(player["character_name"])
            target_option.set_item_metadata(target_option.get_item_count() - 1, player["id"])

func _on_betray_btn_pressed() -> void:
    # 弹出背叛确认弹窗
    var popup = ConfirmationDialog.new()
    popup.title = "⚠️ 警告：背叛搭档"
    popup.size = Vector2(450, 350)

    var vbox = VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 15)

    # 警告文字
    var warn_label = Label.new()
    warn_label.text = "背叛搭档将产生以下后果："
    warn_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))

    # 后果列表
    var shared_count = current_relationship.get("shared_intel_ids", []).size()
    var consequence_list = [
        "• 搭档将获得你们共同收集的所有情报副本（%d 条）" % shared_count,
        "• 你的体面值将下降 10 点",
        "• 你的忠诚记录将增加一次背叛记录",
        "• 累计 3 次背叛将进入\"声名狼藉\"状态，无法被新主子收留"
    ]

    for item in consequence_list:
        var item_label = Label.new()
        item_label.text = item
        item_label.autowrap_mode = TextServer.AUTOWRAP_WORD
        vbox.add_child(item_label)

    # 确认输入
    var input_label = Label.new()
    input_label.text = "\n请输入确认文字："
    var line_edit = LineEdit.new()
    line_edit.placeholder_text = "输入 '我已知晓后果' 后确认"
    line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    popup.add_child(vbox)
    vbox.add_child(input_label)
    vbox.add_child(line_edit)

    popup.get_ok_button().disabled = true
    line_edit.text_changed.connect(func(new_text):
        popup.get_ok_button().disabled = (new_text != "我已知晓后果")
    )

    popup.confirmed.connect(func():
        if not current_relationship.is_empty():
            await RelationshipManager.betray_partner(current_relationship["id"], PlayerState.uid)
            EventBus.show_notification.emit("你已背叛搭档，从此声名受损...")
            _refresh_ui()
    )

    add_child(popup)
    popup.popup_centered()
