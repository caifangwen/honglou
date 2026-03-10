extends Control

# 角色与阶层选择界面脚本，占位逻辑

signal role_selected(role_class: String)

func _on_select_steward_pressed() -> void:
    emit_signal("role_selected", GameConfig.CLASS_STEWARD)

func _on_select_master_pressed() -> void:
    emit_signal("role_selected", GameConfig.CLASS_MASTER)

func _on_select_servant_pressed() -> void:
    emit_signal("role_selected", GameConfig.CLASS_SERVANT)

