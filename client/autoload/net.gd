extends Node
## 서버 연결 (autoload: Net). WebSocket 위에서 JSON 메시지를 주고받고,
## 현재 온라인 대국 정보(방 코드, 내 색, 시작 상태)를 씬 전환 사이에 들고 있는다.

signal connected
signal connection_failed
signal disconnected
signal message_received(msg: Dictionary)

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 8080
const CONNECT_TIMEOUT := 5.0

var _ws: WebSocketPeer
var _state := WebSocketPeer.STATE_CLOSED
var _connect_started := 0.0

## 온라인 대국 정보. game_start를 받으면 채워지고, 연결이 끊기면 비워진다.
var room_code := ""
var my_color := 0
var start_state := {}


func is_open() -> bool:
	return _ws != null and _state == WebSocketPeer.STATE_OPEN


## 온라인 대국이 시작된 상태인지 (연결이 끊기면 정보가 비워져 false가 된다)
func in_game() -> bool:
	return my_color != 0


## "192.168.0.10" 처럼 입력해도 "ws://192.168.0.10:8080" 으로 바꿔 준다.
static func normalize_url(address: String) -> String:
	var url := address.strip_edges()
	if url.is_empty():
		return ""
	if not url.contains("://"):
		url = "ws://" + url
	var host_part := url.get_slice("://", 1)
	if not host_part.contains(":"):
		url += ":%d" % DEFAULT_PORT
	return url


func connect_to_server(address: String) -> Error:
	close()
	var url := normalize_url(address)
	if url.is_empty():
		return ERR_INVALID_PARAMETER
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(url)
	if err != OK:
		_ws = null
		return err
	_state = WebSocketPeer.STATE_CONNECTING
	_connect_started = Time.get_ticks_msec() / 1000.0
	return OK


func close() -> void:
	if _ws:
		_ws.close()
	_ws = null
	_state = WebSocketPeer.STATE_CLOSED
	_clear_session()


func send(msg: Dictionary) -> void:
	if not is_open():
		return
	msg["v"] = PROTOCOL_VERSION
	_ws.send_text(JSON.stringify(msg))


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var new_state := _ws.get_ready_state()
	if new_state == WebSocketPeer.STATE_CONNECTING:
		if Time.get_ticks_msec() / 1000.0 - _connect_started > CONNECT_TIMEOUT:
			_ws.close()
			_ws = null
			_state = WebSocketPeer.STATE_CLOSED
			connection_failed.emit()
		return

	var old_state := _state
	_state = new_state
	if new_state == WebSocketPeer.STATE_OPEN:
		if old_state != WebSocketPeer.STATE_OPEN:
			connected.emit()
		while _ws and _ws.get_available_packet_count() > 0:
			var text := _ws.get_packet().get_string_from_utf8()
			var msg: Variant = JSON.parse_string(text)
			if typeof(msg) == TYPE_DICTIONARY:
				_receive(msg)
	elif new_state == WebSocketPeer.STATE_CLOSED:
		_ws = null
		_clear_session()
		if old_state == WebSocketPeer.STATE_CONNECTING:
			connection_failed.emit()
		else:
			disconnected.emit()


## 테스트에서 서버 메시지를 흉내 낼 때도 쓴다.
func _receive(msg: Dictionary) -> void:
	if msg.get("t") == "game_start":
		room_code = str(msg.code)
		my_color = int(msg.color)
		start_state = msg.state
	elif msg.get("t") == "opponent_left":
		my_color = 0
	message_received.emit(msg)


func _clear_session() -> void:
	room_code = ""
	my_color = 0
	start_state = {}
