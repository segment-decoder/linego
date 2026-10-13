class_name ServerCore
extends RefCounted
## 방 코드 대전 서버의 로직. 소켓과 무관하게 "메시지를 받으면 보낼 메시지를 쌓는" 형태라
## 네트워크 없이 테스트할 수 있다. 전송은 server.gd가 맡는다.
##
## 프로토콜: 모든 메시지는 {"t": 종류, ...} 형태의 JSON. 자세한 목록은 docs/PROTOCOL.md.

const Stone := BoardState.Stone
const PROTOCOL_VERSION := 1
## 헷갈리는 글자(0/O, 1/I/L)를 뺀 방 코드 문자
const CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 4


class Room:
	var code: String
	## [흑 peer, 백 peer]. 아직 상대가 없으면 크기 1.
	var players: Array[int] = []
	var game: GameState
	var rematch_votes := {}

	func color_of(peer: int) -> int:
		var i := players.find(peer)
		return Stone.BLACK if i == 0 else Stone.WHITE if i == 1 else Stone.EMPTY

	func opponent_of(peer: int) -> int:
		for p in players:
			if p != peer:
				return p
		return 0


var rooms := {}  # code -> Room
var peer_room := {}  # peer id -> code
var rng := RandomNumberGenerator.new()
var _outbox: Array = []  # [peer id, message]


## 쌓인 보낼 메시지를 꺼낸다. 각 원소는 [peer id, Dictionary].
func take_outbox() -> Array:
	var out := _outbox
	_outbox = []
	return out


func handle_message(peer: int, msg: Variant) -> void:
	if typeof(msg) != TYPE_DICTIONARY:
		_error(peer, "bad_message")
		return
	match msg.get("t"):
		"create_room":
			_create_room(peer, msg)
		"join_room":
			_join_room(peer, msg)
		"action":
			_action(peer, msg)
		"rematch":
			_rematch(peer)
		"leave":
			_leave(peer)
		_:
			_error(peer, "bad_message")


func handle_disconnect(peer: int) -> void:
	_leave(peer)


func _create_room(peer: int, msg: Dictionary) -> void:
	if not _check_version(peer, msg):
		return
	_leave(peer)
	var room := Room.new()
	room.code = _new_code()
	room.players = [peer]
	rooms[room.code] = room
	peer_room[peer] = room.code
	_send(peer, {"t": "room_created", "code": room.code})


func _join_room(peer: int, msg: Dictionary) -> void:
	if not _check_version(peer, msg):
		return
	var code := str(msg.get("code", "")).strip_edges().to_upper()
	var room: Room = rooms.get(code)
	if room == null:
		_error(peer, "no_such_room")
		return
	if room.players.size() >= 2:
		_error(peer, "room_full")
		return
	if room.players.has(peer):
		_error(peer, "already_in_room")
		return
	_leave(peer)
	room.players.append(peer)
	peer_room[peer] = code
	_start_game(room)


func _start_game(room: Room) -> void:
	room.game = GameState.new()
	room.rematch_votes.clear()
	var state := room.game.to_dict()
	for p in room.players:
		_send(p, {"t": "game_start", "code": room.code, "color": room.color_of(p), "state": state})


func _action(peer: int, msg: Dictionary) -> void:
	var room := _room_of(peer)
	if room == null or room.game == null:
		_error(peer, "not_in_game")
		return
	var game := room.game
	if game.is_over():
		_error(peer, "game_over")
		return
	var color := room.color_of(peer)
	if color != game.current_player:
		_error(peer, "not_your_turn")
		return
	var action := GameState.normalize_action(msg.get("action"))
	var reason := game.validate(action)
	if reason != "":
		_error(peer, reason)
		return
	game.apply(action)
	var update := {"t": "state", "state": game.to_dict(), "last": action, "by": color}
	for p in room.players:
		_send(p, update)


func _rematch(peer: int) -> void:
	var room := _room_of(peer)
	if room == null or room.game == null or not room.game.is_over() or room.players.size() < 2:
		_error(peer, "cannot_rematch")
		return
	room.rematch_votes[peer] = true
	if room.rematch_votes.size() < 2:
		_send(room.opponent_of(peer), {"t": "rematch_requested"})
		return
	# 다시 할 때마다 흑백을 바꾼다.
	room.players.reverse()
	_start_game(room)


func _leave(peer: int) -> void:
	var room := _room_of(peer)
	peer_room.erase(peer)
	if room == null:
		return
	room.players.erase(peer)
	# 한 명이 나가면 방은 닫는다. (재접속은 아직 지원하지 않음)
	for p in room.players:
		peer_room.erase(p)
		_send(p, {"t": "opponent_left"})
	rooms.erase(room.code)


func _room_of(peer: int) -> Room:
	return rooms.get(peer_room.get(peer, ""))


func _check_version(peer: int, msg: Dictionary) -> bool:
	var v: Variant = msg.get("v")
	if typeof(v) not in [TYPE_INT, TYPE_FLOAT] or int(v) != PROTOCOL_VERSION:
		_error(peer, "version_mismatch")
		return false
	return true


func _new_code() -> String:
	while true:
		var code := ""
		for i in CODE_LENGTH:
			code += CODE_CHARS[rng.randi_range(0, CODE_CHARS.length() - 1)]
		if not rooms.has(code):
			return code
	return ""


func _send(peer: int, msg: Dictionary) -> void:
	_outbox.append([peer, msg])


func _error(peer: int, reason: String) -> void:
	_send(peer, {"t": "error", "reason": reason})
