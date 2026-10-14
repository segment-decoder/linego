extends RefCounted
## 게임 화면의 온라인 모드. 서버 메시지는 Net._receive 로 흉내 낸다.

const Stone := BoardState.Stone

var t  # 테스트 러너
var sent: Array = []


func _spawn_online(color: int) -> Node:
	var net: Node = t.root.get_node("Net")
	net.close()
	net._receive({"t": "game_start", "code": "ABCD", "color": color, "state": GameState.new().to_dict()})
	var scene: Node = load("res://scenes/game/game.tscn").instantiate()
	t.root.add_child(scene)
	await t.process_frame
	await t.process_frame
	return scene


func _cleanup(scene: Node) -> void:
	scene.queue_free()
	t.root.get_node("Net").close()
	await t.process_frame


func _world_to_screen(scene: Node, world: Vector2) -> Vector2:
	var camera: BoardCamera = scene.camera
	return (world - camera.position) * camera.zoom.x + camera.get_viewport_rect().size / 2.0


func test_starts_in_online_mode_with_my_color() -> void:
	var scene: Node = await _spawn_online(Stone.WHITE)
	t.check(scene.online)
	t.check_eq(scene.my_color, Stone.WHITE)
	t.check(not scene.can_act(), "백은 첫 수를 둘 수 없다")
	t.check(scene.place_button.disabled, "상대 차례에는 버튼이 꺼진다")
	t.check(scene.turn_label.text.begins_with("상대 차례"))
	var target := _world_to_screen(scene, scene.board_view.intersection_position(1, 1))
	scene.handle_tap(target)
	t.check(scene.board_view.preview.is_empty(), "상대 차례에는 탭이 무시된다")
	await _cleanup(scene)


func test_my_move_waits_for_server_state() -> void:
	var scene: Node = await _spawn_online(Stone.BLACK)
	var net: Node = t.root.get_node("Net")
	t.check(scene.can_act())
	var target := _world_to_screen(scene, scene.board_view.intersection_position(1, 1))
	scene.handle_tap(target)
	scene.handle_tap(target)
	t.check_eq(scene.game.board.get_stone(1, 1), Stone.EMPTY, "서버 확인 전에는 판에 반영하지 않는다")
	t.check(not scene.can_act(), "응답 대기 중")

	net._receive(JSON.parse_string(JSON.stringify({"t": "move", "action": GameState.place_action(1, 1), "by": Stone.BLACK, "turn": 1})))
	t.check_eq(scene.game.board.get_stone(1, 1), Stone.BLACK, "서버가 확정한 수를 적용")
	t.check(scene.board_view.preview.is_empty())
	t.check(not scene.can_act(), "이제 상대 차례")
	await _cleanup(scene)


func test_server_error_unblocks_input() -> void:
	var scene: Node = await _spawn_online(Stone.BLACK)
	var net: Node = t.root.get_node("Net")
	scene.board_view.preview = GameState.place_action(0, 0)
	scene._waiting_server = true
	net._receive({"t": "error", "reason": "occupied"})
	t.check(scene.can_act())
	t.check_eq(scene.hint_label.text, "이미 돌이 있는 곳입니다.")
	await _cleanup(scene)


func test_win_loss_and_rematch_flow() -> void:
	var scene: Node = await _spawn_online(Stone.WHITE)
	var net: Node = t.root.get_node("Net")
	# 오프닝 16수(흑이 맨 윗줄 4개), 흑이 오른쪽 바깥에 세로줄, 백 가로줄, 흑이 5번째 돌.
	var moves := [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1], [3, 0], [3, 1],
		[0, 2], [0, 3], [1, 2], [1, 3], [2, 3], [2, 2], [3, 3], [3, 2]]
	for i in moves.size():
		net._receive({"t": "move", "action": GameState.place_action(moves[i][0], moves[i][1]), "by": Stone.BLACK if i % 2 == 0 else Stone.WHITE, "turn": i + 1})
	t.check(not scene.result_panel.visible, "오프닝에서는 5목이 나오지 않는다")
	net._receive({"t": "move", "action": GameState.line_action(GameState.AXIS_COL, 4), "by": Stone.BLACK, "turn": 17})
	net._receive({"t": "move", "action": GameState.line_action(GameState.AXIS_ROW, 4), "by": Stone.WHITE, "turn": 18})
	net._receive({"t": "move", "action": GameState.place_action(4, 0), "by": Stone.BLACK, "turn": 19})
	t.check(scene.result_panel.visible)
	t.check_eq(scene.result_label.text, "패배")

	net._receive({"t": "rematch_requested"})
	t.check(scene.result_info_label.text.contains("한 판 더"))
	net._receive({"t": "game_start", "code": "ABCD", "color": Stone.BLACK, "state": GameState.new().to_dict()})
	t.check(not scene.result_panel.visible, "새 게임이 시작되면 결과 창이 닫힌다")
	t.check_eq(scene.my_color, Stone.BLACK)
	t.check(scene.can_act())
	await _cleanup(scene)


func test_out_of_order_move_is_desync() -> void:
	var scene: Node = await _spawn_online(Stone.BLACK)
	t.root.get_node("Net")._receive({"t": "move", "action": GameState.place_action(1, 1), "by": Stone.BLACK, "turn": 5})
	t.check(scene.result_panel.visible, "순서가 어긋난 수는 동기화 오류로 처리")
	t.check_eq(scene.game.board.get_stone(1, 1), Stone.EMPTY)
	await _cleanup(scene)


func test_opponent_left_shows_panel() -> void:
	var scene: Node = await _spawn_online(Stone.BLACK)
	t.root.get_node("Net")._receive({"t": "opponent_left"})
	t.check(scene.result_panel.visible)
	t.check_eq(scene.result_info_label.text, "상대가 나갔습니다.")
	t.check(scene.rematch_button.disabled)
	await _cleanup(scene)


func test_local_game_is_not_online() -> void:
	t.root.get_node("Net").close()
	var scene: Node = load("res://scenes/game/game.tscn").instantiate()
	t.root.add_child(scene)
	await t.process_frame
	t.check(not scene.online)
	t.check(scene.can_act())
	scene.queue_free()
	await t.process_frame


func test_url_normalization() -> void:
	var net: Node = t.root.get_node("Net")
	t.check_eq(net.normalize_url("192.168.0.10"), "ws://192.168.0.10:8080")
	t.check_eq(net.normalize_url(" 192.168.0.10:9000 "), "ws://192.168.0.10:9000")
	t.check_eq(net.normalize_url("wss://linego.example.com"), "wss://linego.example.com:8080")
	t.check_eq(net.normalize_url(""), "")
