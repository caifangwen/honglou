extends Node

@warning_ignore("unused_signal")

# 全局信号总线，解耦跨场景通信

# 导航信号
signal navigate_to(scene_name: String)
signal navigate_back()

# 流言系统信号
signal rumor_published(rumor_data: Dictionary)
signal rumor_fermented(rumor_id: String, stage: int)
signal rumor_suppressed(rumor_id: String)

# 批条/行动系统信号
signal action_submitted(action_data: Dictionary)
signal action_approved(action_id: String)
signal action_rejected(action_id: String, reason: String)

# 情报系统信号
signal intel_acquired(intel_data: Dictionary)
signal intel_sold(intel_id: String, buyer_uid: String)

# 查账系统信号
signal audit_initiated(target_uid: String, evidence: Array)
signal audit_verdict(target_uid: String, result: String)

# 突发事件信号
signal special_event_started(event_name: String, event_data: Dictionary)
signal special_event_ended(event_name: String)

# 社交信号
signal message_sent(from_uid: String, to_uid: String, content: String)
signal relation_changed(uid_a: String, uid_b: String, relation_type: String)

# 系统通用信号
signal show_notification(message: String)

