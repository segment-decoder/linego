extends RefCounted
## 게임 화면을 실제로 띄워 탭 입력으로 한 수씩 두어 보는 통합 테스트.

const Stone := BoardState.Stone

var t  # 테스트 러너


func _world_to_screen(scene: Node, world: Vector2) -> Vector2:
	var camera: BoardCamera = scene.camera
	return (world - camera.position) * camera.zoom.x + camera.get_viewport_rect().size / 2.0


func _spawn() -> Node:
	var scene: Node = load("res://scenes/game/game.tscn").instantiate()
	t.root.add_child(scene)
	await t.process_frame
	await t.process_frame
	return scene


func test_tap_twice_places_stone() -> void:
	var scene: Node = await _spawn()
	var view: BoardView = scene.board_view
	var target := _world_to_screen(scene, view.intersection_position(1, 2))
	t.check(scene.board_area.get_global_rect().has_point(target), "판이 BoardArea 안에 보여야 한다")
	scene.handle_tap(target)
	t.check_eq(view.preview, GameState.place_action(1, 2), "첫 탭은 미리보기")
	t.check_eq(scene.game.board.get_stone(1, 2), Stone.EMPTY)
	scene.handle_tap(target)
	t.check_eq(scene.game.board.get_stone(1, 2), Stone.BLACK, "같은 곳 두 번째 탭은 확정")
	t.check_eq(scene.game.current_player, Stone.WHITE)
	scene.queue_free()


func test_line_mode_inserts_column_and_keeps_stone_in_view() -> void:
	var scene: Node = await _spawn()
	var view: BoardView = scene.board_view
	scene.apply_action(GameState.place_action(3, 0))
	var before := _world_to_screen(scene, view.intersection_position(3, 0))
	scene.col_button.pressed.emit()
	# 카메라 중심(1.5칸)보다 왼쪽에 줄을 그으면, 카메라가 보던 오른쪽 부분이 화면에 고정되어야 한다.
	var gap := _world_to_screen(scene, Vector2(view.gap_coordinate(1), view.CELL))
	scene.handle_tap(gap)
	t.check_eq(view.preview, GameState.line_action(GameState.AXIS_COL, 1))
	scene.confirm_button.pressed.emit()
	t.check_eq(scene.game.board.width, 5)
	t.check_eq(scene.game.board.get_stone(4, 0), Stone.BLACK, "줄 오른쪽 돌은 한 칸 밀린다")
	t.check_eq(scene.mode, scene.Mode.PLACE, "행동 후 돌 놓기 모드로 돌아간다")
	var after := _world_to_screen(scene, view.intersection_position(4, 0))
	t.check(before.distance_to(after) < 1.0, "밀린 돌이 화면에서 같은 자리에 보여야 한다")
	scene.queue_free()


func test_win_shows_result_panel() -> void:
	var scene: Node = await _spawn()
	scene.game.board = BoardState.from_text("XXXX.\n.....")
	scene.board_view.game = scene.game
	scene.apply_action(GameState.place_action(4, 0))
	t.check_eq(scene.game.winner, Stone.BLACK)
	t.check(scene.result_panel.visible)
	t.check_eq(scene.result_label.text, "흑 승리!")
	scene.queue_free()
