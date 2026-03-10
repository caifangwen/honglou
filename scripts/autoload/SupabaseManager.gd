extends Node

# Supabase REST API 封装
# 使用 Godot 4 HTTPRequest 节点进行通信

const SUPABASE_URL: String = "https://daotqqwsxvydxqttmams.supabase.co"
const ANON_KEY: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRhb3RxcXdzeHZ5ZHhxdHRtYW1zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNTg2NDYsImV4cCI6MjA4ODczNDY0Nn0.14c25wXFIAhoe1sJhdM7xJbEkJo3ihUqpu-VeXE680U"

signal request_completed(endpoint: String, response_code: int, result: Array)
signal request_failed(endpoint: String, error_message: String)

# 获取通用请求头
func _get_headers() -> Array:
    return [
        "apikey: " + ANON_KEY,
        "Authorization: Bearer " + ANON_KEY,
        "Content-Type: application/json",
        "Prefer: return=representation"
    ]

# 发送 GET 请求
func get_from_table(table_name: String, query: String = "") -> void:
    var url = SUPABASE_URL + "/rest/v1/" + table_name
    if query != "":
        url += "?" + query
    
    var http_request = HTTPRequest.new()
    add_child(http_request)
    http_request.request_completed.connect(self._on_request_completed.bind(http_request, table_name))
    
    var error = http_request.request(url, _get_headers(), HTTPClient.METHOD_GET)
    if error != OK:
        request_failed.emit(table_name, "HTTP Request Error: " + str(error))
        http_request.queue_free()

# 发送 POST 请求（插入数据）
func insert_into_table(table_name: String, data: Dictionary) -> void:
    var url = SUPABASE_URL + "/rest/v1/" + table_name
    var http_request = HTTPRequest.new()
    add_child(http_request)
    http_request.request_completed.connect(self._on_request_completed.bind(http_request, table_name))
    
    var json_data = JSON.stringify(data)
    var error = http_request.request(url, _get_headers(), HTTPClient.METHOD_POST, json_data)
    if error != OK:
        request_failed.emit(table_name, "HTTP Request Error: " + str(error))
        http_request.queue_free()

# 发送 PATCH 请求（更新数据）
func update_table(table_name: String, query: String, data: Dictionary) -> void:
    var url = SUPABASE_URL + "/rest/v1/" + table_name + "?" + query
    var http_request = HTTPRequest.new()
    add_child(http_request)
    http_request.request_completed.connect(self._on_request_completed.bind(http_request, table_name))
    
    var json_data = JSON.stringify(data)
    var error = http_request.request(url, _get_headers(), HTTPClient.METHOD_PATCH, json_data)
    if error != OK:
        request_failed.emit(table_name, "HTTP Request Error: " + str(error))
        http_request.queue_free()

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_node: HTTPRequest, endpoint: String) -> void:
    http_node.queue_free()
    
    if result != HTTPRequest.RESULT_SUCCESS:
        request_failed.emit(endpoint, "Request failed with result code: " + str(result))
        return

    var response_text = body.get_string_from_utf8()
    var json = JSON.new()
    var parse_err = json.parse(response_text)
    
    if parse_err != OK:
        if response_code >= 200 and response_code < 300:
            # 可能是空的返回
            request_completed.emit(endpoint, response_code, [])
        else:
            request_failed.emit(endpoint, "JSON Parse Error: " + json.get_error_message())
        return
        
    var data = json.get_data()
    if data is Array:
        request_completed.emit(endpoint, response_code, data)
    elif data is Dictionary:
        request_completed.emit(endpoint, response_code, [data])
    else:
        request_completed.emit(endpoint, response_code, [])
