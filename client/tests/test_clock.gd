extends RefCounted
## 대국 시계와 시간 초과 (코어, 서버, 화면)

const Stone := BoardState.Stone
const A := 1
const B := 2

var t  # 테스트 러너


func test_clock_counts_only_the_running_side() -> void:
	var clock := ChessClock.new(5)
	clock.start(Stone.BLACK, 0)
	t.check_eq(clock.remaining(Stone.BLACK, 10000), 290000)
	t.check_eq(clock.remaining(Stone.WHITE, 10000), 300000)
	clock.switch_to(Stone.WHITE, 10000)
	t.check_eq(clock.remaining(Stone.BLACK, 50000), 290000, "흑 시간은 멈춘다")
	t.check_eq(clock.remaining(Stone.WHITE, 15000), 295000)
	t.check_eq(clock.flagged(15000), 0)
	t.check_eq(clock.flagged(310001), Stone.WHITE)
	t.check_eq(clock.remaining(Stone.WHITE, 999999), 0, "음수가 되지 않는다")


func test_clock_dict_and_format() -> void:
	var clock := ChessClock.new(3)
	clock.start(Stone.WHITE, 1000)
	var copy := ChessClock.from_dict(JSON.parse_string(JSON.stringify(clock.to_dict(6000))), 0)
	t.check_eq(copy.remaining(Stone.WHITE, 0), 175000)
	t.check_eq(copy.running, Stone.WHITE)
	t.check_eq(copy.minutes, 3)
	t.check_eq(ChessClock.format(175000), "2:55")
	t.check_eq(ChessClock.format(59001), "1:00", "남은 초는 올림")
	t.check_eq(ChessClock.format(0), "0:00")


func _start_server_room(minutes: Variant) -> ServerCore:
	var core := ServerCore.new()
	core.fake_now_ms = 0
	var create := {"t": "create_room", "v": ServerCore.PROTOCOL_VERSION}
	if minutes != null:
		create["minutes"] = minutes
	core.handle_message(A, create)
	var code: String = core.take_outbox()[0][1].code
	core.handle_message(B, {"t": "join_room", "code": code, "v": ServerCore.PROTOCOL_VERSION})
	return core


func test_server_room_minutes() -> void:
	var core := _start_server_room(20)
	var start: Dictionary = core.take_outbox()[0][1]
	t.check_eq(start.clock.black_ms, 1200000)
	t.check_eq(start.clock.running, Stone.BLACK)
	t.check_eq(GameState.from_dict(start.state).max_turns, 0, "시계가 있으면 수 제한 없음")
	core = _start_server_room(7)
	t.check_eq(core.take_outbox()[0][1].clock.minutes, 10, "허용되지 않은 시간은 기본 10분")
	core = _start_server_room(null)
	t.check_eq(core.take_outbox()[0][1].clock.minutes, 10, "생략하면 기본 10분")


func test_server_move_switches_clock() -> void:
	var core := _start_server_room(5)
	core.take_outbox()
	core.fake_now_ms = 12000
	core.handle_message(A, {"t": "action", "action": GameState.place_action(0, 0), "v": 3})
	var move: Dictionary = core.take_outbox()[0][1]
	t.check_eq(move.clock.black_ms, 288000)
	t.check_eq(move.clock.running, Stone.WHITE)


func test_server_timeout_by_tick_and_late_move() -> void:
	var core := _start_server_room(5)
	core.take_outbox()
	core.fake_now_ms = 299999
	core.tick()
	t.check(core.take_outbox().is_empty(), "아직 시간이 남았다")
	core.fake_now_ms = 300000
	core.tick()
	var out := core.take_outbox()
	t.check_eq(out.size(), 2, "두 사람 모두에게 알림")
	t.check_eq(out[0][1].t, "timeout")
	t.check_eq(out[0][1].loser, Stone.BLACK)
	var game: GameState = core.rooms.values()[0].game
	t.check_eq(game.winner, Stone.WHITE)
	t.check_eq(game.end_reason, "timeout")

	# 시간이 지난 뒤에 도착한 수는 받지 않는다 (tick 전에 도착해도 마찬가지).
	core = _start_server_room(5)
	core.take_outbox()
	core.fake_now_ms = 320000
	core.handle_message(A, {"t": "action", "action": GameState.place_action(0, 0), "v": 3})
	out = core.take_outbox()
	t.check(out.any(func(item): return item[1].t == "timeout"))
	t.check(out.any(func(item): return item[0] == A and item[1].get("reason") == "game_over"))


func test_online_timeout_message_shows_result() -> void:
	var net: Node = t.root.get_node("Net")
	net.close()
	var clock := ChessClock.new(5)
	clock.start(Stone.BLACK, 0)
	net._receive({"t": "game_start", "code": "ABCD", "color": Stone.WHITE, "state": GameState.new().to_dict(), "clock": clock.to_dict(0)})
	var scene: Node = load("res://scenes/game/game.tscn").instantiate()
	t.root.add_child(scene)
	await t.process_frame
	t.check(scene.clock != null)
	t.check(scene.clock_bar.visible)
	net._receive({"t": "timeout", "loser": Stone.BLACK, "clock": {"minutes": 5, "black_ms": 0, "white_ms": 300000, "running": 0}})
	t.check(scene.result_panel.visible)
	t.check_eq(scene.result_label.text, "승리!")
	t.check(scene.result_info_label.text.contains("시간 초과"))
	scene.queue_free()
	net.close()
	await t.process_frame


func test_local_clock_flag_ends_game() -> void:
	var settings: Node = t.root.get_node("Settings")
	var was: bool = settings.local_clock
	settings.local_clock = true
	t.root.get_node("Net").close()
	var scene: Node = load("res://scenes/game/game.tscn").instantiate()
	t.root.add_child(scene)
	await t.process_frame
	t.check_eq(scene.game.max_turns, 0)
	scene.clock.remaining_ms[Stone.BLACK] = 0
	await t.process_frame
	t.check(scene.game.is_over())
	t.check_eq(scene.result_label.text, "백 승리!")
	t.check(scene.result_info_label.text.contains("흑 시간 초과"))
	scene.queue_free()

	settings.local_clock = false
	scene = load("res://scenes/game/game.tscn").instantiate()
	t.root.add_child(scene)
	await t.process_frame
	t.check(scene.clock == null, "시간 제한을 끄면 시계 없음")
	t.check_eq(scene.game.max_turns, GameState.MAX_TURNS, "대신 450수 제한")
	scene.queue_free()
	settings.local_clock = was
	await t.process_frame


func test_no_turns_left_shown_without_turn_limit() -> void:
	var settings: Node = t.root.get_node("Settings")
	var was: bool = settings.local_clock
	settings.local_clock = true
	var scene: Node = load("res://scenes/game/game.tscn").instantiate()
	t.root.add_child(scene)
	await t.process_frame
	t.check(not scene.turn_label.text.contains("남은 수"), scene.turn_label.text)
	scene.queue_free()
	settings.local_clock = was
	await t.process_frame
