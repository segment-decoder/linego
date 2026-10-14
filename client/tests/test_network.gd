extends RefCounted
## 실제 WebSocket으로 서버에 붙어 보는 통합 테스트 (localhost).

const Stone := BoardState.Stone
const PORT := 18765

var t  # 테스트 러너


func _connect() -> WebSocketPeer:
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % PORT)
	return ws


func _send(ws: WebSocketPeer, msg: Dictionary) -> void:
	msg["v"] = ServerCore.PROTOCOL_VERSION
	ws.send_text(JSON.stringify(msg))


## 서버와 클라이언트를 돌리면서 ws에 메시지가 올 때까지 기다린다 (최대 약 3초).
func _receive(server: LinegoServer, ws: WebSocketPeer) -> Dictionary:
	for i in 180:
		server.poll()
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			return JSON.parse_string(ws.get_packet().get_string_from_utf8())
		await t.process_frame
	return {}


func _wait_open(server: LinegoServer, peers: Array) -> bool:
	for i in 180:
		server.poll()
		var all_open := true
		for ws: WebSocketPeer in peers:
			ws.poll()
			all_open = all_open and ws.get_ready_state() == WebSocketPeer.STATE_OPEN
		if all_open:
			return true
		await t.process_frame
	return false


func test_two_clients_play_over_websocket() -> void:
	var server := LinegoServer.new()
	t.check_eq(server.start(PORT, "127.0.0.1"), OK, "서버 시작")
	var a := _connect()
	var b := _connect()
	t.check(await _wait_open(server, [a, b]), "두 클라이언트 접속")

	_send(a, {"t": "create_room"})
	var created := await _receive(server, a)
	t.check_eq(created.get("t"), "room_created")

	_send(b, {"t": "join_room", "code": created.get("code", "")})
	var start_a := await _receive(server, a)
	var start_b := await _receive(server, b)
	t.check_eq(start_a.get("t"), "game_start")
	t.check_eq(int(start_a.get("color", 0)), Stone.BLACK)
	t.check_eq(int(start_b.get("color", 0)), Stone.WHITE)

	_send(a, {"t": "action", "action": GameState.place_action(2, 1)})
	var state_b := await _receive(server, b)
	t.check_eq(state_b.get("t"), "move")
	t.check_eq(GameState.normalize_action(state_b.get("action")), GameState.place_action(2, 1))
	await _receive(server, a)

	# 잘못된 JSON에도 서버는 죽지 않고 오류로 답한다.
	b.send_text("{not json")
	t.check_eq((await _receive(server, b)).get("reason"), "bad_message")

	a.close()
	t.check_eq((await _receive(server, b)).get("t"), "opponent_left", "상대가 끊기면 알림")

	b.close()
	server.stop()
	server.free()
