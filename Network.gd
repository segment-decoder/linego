# Network.gd
extends Node

# Godot에 내장된 공식 WebSocketClient 클래스
var ws_client = WebSocketClient.new()

# 시그널 정의
signal connection_succeeded
signal connection_failed
signal match_found(data)

# 서버 주소
const SERVER_URL = "ws://localhost:8080"


# _process는 내장 클라이언트를 위해 반드시 필요합니다.
func _process(delta):
	if ws_client.get_connection_status() == WebSocketClient.CONNECTION_STATUS_CONNECTED:
		ws_client.poll()


func connect_to_server():
	print("Connecting to server...")
	var err = ws_client.connect_to_url(SERVER_URL)
	if err != OK:
		print("Error connecting to server.")
		emit_signal("connection_failed")
		return

	# WebSocket 클라이언트의 시그널들을 이 스크립트의 함수와 연결
	ws_client.connection_succeeded.connect(_on_connection_succeeded)
	ws_client.connection_error.connect(_on_connection_failed)
	ws_client.data_received.connect(_on_data_received)
	ws_client.connection_closed.connect(_on_connection_closed)


func send_message(payload: Dictionary):
	# 연결 상태 확인은 get_connection_status()를 사용합니다.
	if ws_client.get_connection_status() == WebSocketClient.CONNECTION_STATUS_CONNECTED:
		var json_string = JSON.stringify(payload)
		ws_client.send_text(json_string)
	else:
		print("Not connected to server. Cannot send message.")


# --- Private Functions (WebSocket Signals) ---

func _on_connection_succeeded(protocol=""):
	print("Connection Succeeded!")
	emit_signal("connection_succeeded")


func _on_connection_failed():
	print("Connection Failed!")
	emit_signal("connection_failed")


func _on_connection_closed(was_clean = false):
	print("Connection closed.")


# 데이터 수신 방식
func _on_data_received():
	var packet = ws_client.get_peer(1).get_packet()
	var json_string = packet.get_string_from_utf8()
	var response = JSON.parse_string(json_string)
	
	if response and response.has("type"):
		match response.type:
			"matchFound":
				print("Match Found! Data: ", response.data)
				emit_signal("match_found", response.data)
			_:
				print("Unknown message type received: ", response.type)
