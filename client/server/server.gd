class_name LinegoServer
extends Node
## WebSocket 전송 계층. 접속을 받아 JSON 메시지를 ServerCore에 넘기고, 결과를 돌려보낸다.

const DEFAULT_PORT := 8080
## 핸드셰이크가 이 시간(초) 안에 끝나지 않으면 끊는다.
const HANDSHAKE_TIMEOUT := 5.0

var core := ServerCore.new()
var _tcp := TCPServer.new()
var _peers := {}  # peer id -> WebSocketPeer
var _connected_at := {}  # peer id -> 접속 시각 (초)
var _next_id := 1


func start(port: int = DEFAULT_PORT, bind_address: String = "*") -> Error:
	return _tcp.listen(port, bind_address)


func stop() -> void:
	for ws: WebSocketPeer in _peers.values():
		ws.close()
	_peers.clear()
	_tcp.stop()


func is_listening() -> bool:
	return _tcp.is_listening()


func _process(_delta: float) -> void:
	poll()


func poll() -> void:
	if not _tcp.is_listening():
		return
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		if ws.accept_stream(_tcp.take_connection()) == OK:
			_peers[_next_id] = ws
			_connected_at[_next_id] = Time.get_ticks_msec() / 1000.0
			_next_id += 1

	var now := Time.get_ticks_msec() / 1000.0
	for id: int in _peers.keys():
		var ws: WebSocketPeer = _peers[id]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_CONNECTING:
				if now - _connected_at[id] > HANDSHAKE_TIMEOUT:
					ws.close()
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					var packet := ws.get_packet()
					if ws.was_string_packet():
						core.handle_message(id, _parse(packet.get_string_from_utf8()))
			WebSocketPeer.STATE_CLOSED:
				_peers.erase(id)
				_connected_at.erase(id)
				core.handle_disconnect(id)
	_flush()


func _flush() -> void:
	for item in core.take_outbox():
		var ws: WebSocketPeer = _peers.get(item[0])
		if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(JSON.stringify(item[1]))


## 잘못된 JSON이면 null (ServerCore가 bad_message로 응답한다).
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
