extends RefCounted
## 서버 로직 테스트 (소켓 없이 ServerCore만).

const Stone := BoardState.Stone
const A := 1  # 방 만든 사람
const B := 2  # 참가한 사람
const C := 3  # 제3자

var t  # 테스트 러너
var core: ServerCore


func _send(peer: int, msg: Dictionary) -> Array:
	if not msg.has("v"):
		msg["v"] = ServerCore.PROTOCOL_VERSION
	core.handle_message(peer, msg)
	return core.take_outbox()


## outbox에서 peer에게 간 메시지만 골라낸다.
func _to(outbox: Array, peer: int) -> Array:
	return outbox.filter(func(item): return item[0] == peer).map(func(item): return item[1])


func _start_room() -> String:
	core = ServerCore.new()
	core.rng.seed = 1
	var code: String = _to(_send(A, {"t": "create_room"}), A)[0].code
	_send(B, {"t": "join_room", "code": code})
	return code


func test_create_room_returns_code() -> void:
	core = ServerCore.new()
	var out := _to(_send(A, {"t": "create_room"}), A)
	t.check_eq(out.size(), 1)
	t.check_eq(out[0].t, "room_created")
	t.check_eq(out[0].code.length(), 4)


func test_join_starts_game_for_both_with_colors() -> void:
	core = ServerCore.new()
	var code: String = _to(_send(A, {"t": "create_room"}), A)[0].code
	var out := _send(B, {"t": "join_room", "code": code.to_lower()})
	var to_a := _to(out, A)
	var to_b := _to(out, B)
	t.check_eq(to_a[0].t, "game_start")
	t.check_eq(to_a[0].color, Stone.BLACK, "방을 만든 사람이 첫 판 흑")
	t.check_eq(to_b[0].color, Stone.WHITE)
	t.check_eq(GameState.from_dict(to_b[0].state).board.width, 4)


func test_join_errors() -> void:
	var code := _start_room()
	t.check_eq(_to(_send(C, {"t": "join_room", "code": "ZZZZ"}), C)[0].reason, "no_such_room")
	t.check_eq(_to(_send(C, {"t": "join_room", "code": code}), C)[0].reason, "room_full")
	t.check_eq(_to(_send(C, {"t": "create_room", "v": 99}), C)[0].reason, "version_mismatch")
	t.check_eq(_to(_send(C, {"t": "create_room", "v": "x"}), C)[0].reason, "version_mismatch")


func test_bad_messages_get_error_not_crash() -> void:
	core = ServerCore.new()
	core.handle_message(A, null)
	core.handle_message(A, [1, 2])
	core.handle_message(A, {"t": "fly"})
	var out := _to(core.take_outbox(), A)
	t.check_eq(out.size(), 3)
	for msg in out:
		t.check_eq(msg.reason, "bad_message")
	t.check_eq(_to(_send(A, {"t": "action", "action": GameState.place_action(0, 0)}), A)[0].reason, "not_in_game")


func test_actions_are_validated_and_broadcast() -> void:
	_start_room()
	var out := _send(B, {"t": "action", "action": GameState.place_action(0, 0)})
	t.check_eq(_to(out, B)[0].reason, "not_your_turn", "백은 먼저 둘 수 없다")
	t.check(_to(out, A).is_empty())

	out = _send(A, {"t": "action", "action": {"type": "place", "x": 9, "y": 9}})
	t.check_eq(_to(out, A)[0].reason, "out_of_board")

	out = _send(A, {"t": "action", "action": {"type": "place", "x": 1.0, "y": 2.0}})
	for peer in [A, B]:
		var msg: Dictionary = _to(out, peer)[0]
		t.check_eq(msg.t, "move")
		t.check_eq(msg.action, GameState.place_action(1, 2), "정규화된 수가 전달된다")
		t.check_eq(msg.by, Stone.BLACK)
		t.check_eq(msg.turn, 1)
		t.check(not msg.has("state"), "판 전체는 보내지 않는다")

	var game: GameState = core.rooms.values()[0].game
	out = _send(B, {"t": "action", "action": GameState.line_action(GameState.AXIS_COL, 0)})
	t.check_eq(_to(out, A)[0].turn, 2)
	t.check_eq(game.board.width, 5)
	t.check_eq(game.board.get_stone(2, 2), Stone.BLACK, "줄 긋기도 서버에서 적용된다")
	t.check_eq(game.current_player, Stone.BLACK)


func test_win_then_rematch_swaps_colors() -> void:
	var code := _start_room()
	var room: ServerCore.Room = core.rooms[code]
	room.game.board = BoardState.from_text("XXXX.\n.....")
	var out := _send(A, {"t": "action", "action": GameState.place_action(4, 0)})
	t.check_eq(_to(out, B)[0].t, "move")
	t.check_eq(room.game.winner, Stone.BLACK)

	out = _send(A, {"t": "action", "action": GameState.place_action(0, 1)})
	t.check_eq(_to(out, A)[0].reason, "game_over")

	out = _send(A, {"t": "rematch"})
	t.check_eq(_to(out, B)[0].t, "rematch_requested")
	t.check(_to(out, A).is_empty())
	out = _send(B, {"t": "rematch"})
	t.check_eq(_to(out, A)[0].t, "game_start")
	t.check_eq(_to(out, A)[0].color, Stone.WHITE, "다시 하면 흑백이 바뀐다")
	t.check_eq(_to(out, B)[0].color, Stone.BLACK)
	t.check_eq(GameState.from_dict(_to(out, B)[0].state).board.to_text(), BoardState.new().to_text())


func test_rematch_not_allowed_mid_game() -> void:
	_start_room()
	t.check_eq(_to(_send(A, {"t": "rematch"}), A)[0].reason, "cannot_rematch")


func test_disconnect_closes_room_and_notifies_opponent() -> void:
	var code := _start_room()
	core.handle_disconnect(A)
	var out := core.take_outbox()
	t.check_eq(_to(out, B)[0].t, "opponent_left")
	t.check(not core.rooms.has(code))
	t.check(core.peer_room.is_empty())
	t.check_eq(_to(_send(B, {"t": "action", "action": GameState.place_action(0, 0)}), B)[0].reason, "not_in_game")


func test_creator_leaving_before_join_removes_room() -> void:
	core = ServerCore.new()
	var code: String = _to(_send(A, {"t": "create_room"}), A)[0].code
	_send(A, {"t": "leave"})
	t.check(not core.rooms.has(code))
	t.check_eq(_to(_send(B, {"t": "join_room", "code": code}), B)[0].reason, "no_such_room")


func test_room_codes_avoid_confusing_characters() -> void:
	core = ServerCore.new()
	for i in 200:
		var code: String = _to(_send(i + 100, {"t": "create_room"}), i + 100)[0].code
		for ch in "0O1IL":
			t.check(not code.contains(ch), "코드 %s 에 %s" % [code, ch])
	t.check_eq(core.rooms.size(), 200, "코드는 서로 겹치지 않는다")
