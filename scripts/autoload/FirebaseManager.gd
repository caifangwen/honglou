extends Node

# Firebase 读写封装，挂载为 Autoload
# 注意：需要集成 GodotFirebase 插件后，将占位函数替换为真实调用

const BASE_URL: String = "https://your-project.firebaseio.com"

# 数据库路径常量
const PATH_GAMES: String = "/games"
const PATH_PLAYERS: String = "/players"
const PATH_TREASURY: String = "/treasury"
const PATH_ACTIONS_QUEUE: String = "/actions_queue"
const PATH_RUMORS: String = "/rumors"
const PATH_EVENTS: String = "/events"

signal data_loaded(path: String, data: Dictionary)
signal data_saved(path: String)
signal firebase_error(path: String, error: String)

# 占位：读取数据
func read(path: String) -> void:
    # TODO: 替换为 Firebase.Database.get_node(path).get_value()
    push_warning("FirebaseManager: read() 未实现 - path: " + path)

# 占位：写入数据
func write(path: String, data: Dictionary) -> void:
    # TODO: 替换为 Firebase.Database.get_node(path).set_value(data)
    push_warning("FirebaseManager: write() 未实现 - path: " + path)

# 占位：监听实时变化
func listen(path: String) -> void:
    # TODO: 替换为 Firebase.Database.get_node(path).child_changed.connect(...)
    push_warning("FirebaseManager: listen() 未实现 - path: " + path)

