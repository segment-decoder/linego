extends RefCounted

const Stone := BoardState.Stone

var t  # 테스트 러너


## 오프닝(4×4를 돌로 채우기)을 끝낸 게임. 흑 8, 백 8, 5목 없음. 흑 차례.
func _after_opening() -> GameState:
	var game := GameState.new()
	var order := [[0, 0], [2, 0], [1, 0], [3, 0], [2, 1], [0, 1], [3, 1], [1, 1],
		[0, 2], [2, 2], [1, 2], [3, 2], [2, 3], [0, 3], [3, 3], [1, 3]]
	for p in order:
		game.apply(GameState.place_action(p[0], p[1]))
	return game


func _game_with(text: String, player: int = Stone.BLACK) -> GameState:
	var game := GameState.new()
	game.board = BoardState.from_text(text)
	game.current_player = player
	return game


func test_black_moves_first_and_turns_alternate() -> void:
	var game := GameState.new()
	t.check_eq(game.current_player, Stone.BLACK)
	t.check(game.apply(GameState.place_action(0, 0)))
	t.check_eq(game.current_player, Stone.WHITE)
	t.check(game.apply(GameState.place_action(1, 0)))
	t.check_eq(game.current_player, Stone.BLACK)
	t.check_eq(game.history.size(), 2)


func test_opening_allows_only_stones_until_4x4_is_full() -> void:
	var game := GameState.new()
	t.check(game.in_opening())
	t.check_eq(game.validate(GameState.line_action(GameState.AXIS_COL, 0)), "opening")
	t.check(not game.apply(GameState.line_action(GameState.AXIS_COL, 0)))
	game = _after_opening()
	t.check(not game.in_opening(), "16칸을 채우면 오프닝 끝")
	t.check_eq(game.turn_count(), 16)
	t.check_eq(game.current_player, Stone.BLACK, "17수째는 흑")
	t.check(not game.is_over(), "4×4에서는 5목이 나올 수 없다")
	t.check(game.apply(GameState.line_action(GameState.AXIS_COL, 4)))
	t.check_eq(game.board.width, 5)
	t.check(not game.in_opening(), "판이 커진 뒤에는 다시 오프닝이 되지 않는다")


func test_opening_survives_json() -> void:
	var game := GameState.new()
	game.apply(GameState.place_action(0, 0))
	t.check(GameState.from_dict(JSON.parse_string(JSON.stringify(game.to_dict()))).in_opening())


func test_invalid_actions_are_rejected() -> void:
	var game := _after_opening()
	t.check_eq(game.validate(GameState.place_action(1, 1)), "occupied")
	t.check_eq(game.validate(GameState.place_action(4, 0)), "out_of_board")
	t.check_eq(game.validate(GameState.line_action(GameState.AXIS_COL, 5)), "bad_index")
	t.check_eq(game.validate(GameState.line_action(GameState.AXIS_ROW, -1)), "bad_index")
	t.check_eq(game.validate(GameState.line_action("diag", 0)), "bad_action")
	t.check_eq(game.validate({"type": "pass"}), "bad_action")
	t.check_eq(game.validate({"type": "place", "x": "1", "y": 2}), "bad_action", "문자열 좌표")
	t.check_eq(game.validate({"type": "place", "x": null}), "bad_action")
	t.check_eq(game.validate("place"), "bad_action")
	t.check(not game.apply(GameState.place_action(1, 1)))
	t.check_eq(game.current_player, Stone.BLACK, "실패한 행동은 턴을 넘기지 않는다")


func test_placing_fifth_stone_wins() -> void:
	var game := _game_with("XXXX..\n......")
	t.check(game.apply(GameState.place_action(4, 0)))
	t.check_eq(game.winner, Stone.BLACK)
	t.check(game.is_over())
	t.check_eq(game.validate(GameState.place_action(0, 1)), "game_over")


func test_placing_sixth_stone_does_not_win() -> void:
	var game := _game_with("XXXXX..\n.......")
	# 이미 5목이 있지만 그 옆에 놓아 6목이 되면 승리가 아니다.
	game.apply(GameState.place_action(5, 0))
	t.check_eq(game.winner, Stone.EMPTY)
	t.check_eq(game.current_player, Stone.WHITE)


func test_line_that_creates_five_does_not_win_immediately() -> void:
	var game := _game_with("XXXXXX\n......")
	game.apply(GameState.line_action(GameState.AXIS_COL, 5))
	t.check_eq(game.board.to_text(), "XXXXX.X\n.......")
	t.check_eq(game.winner, Stone.EMPTY, "줄긋기로는 승리하지 않는다")
	t.check_eq(game.current_player, Stone.WHITE)
	# 백이 막지 못하면, 흑이 5목을 망가뜨리지 않는 아무 곳에 돌을 놓아 승리한다.
	game.apply(GameState.place_action(0, 1))
	game.apply(GameState.place_action(6, 1))
	t.check_eq(game.winner, Stone.BLACK)


func test_placing_next_to_line_made_five_breaks_it() -> void:
	var game := _game_with("XXXXX..\n.......")
	game.current_player = Stone.BLACK
	game.apply(GameState.place_action(5, 0))
	t.check_eq(game.winner, Stone.EMPTY, "5목 옆에 놓으면 6목이 되어 승리 아님")


func test_opponent_can_cut_five_with_a_line() -> void:
	var game := _game_with("XXXXX.\n......", Stone.WHITE)
	game.apply(GameState.line_action(GameState.AXIS_COL, 2))
	t.check(not game.board.has_exact_five(Stone.BLACK))
	game.apply(GameState.place_action(1, 1))
	t.check_eq(game.winner, Stone.EMPTY)


func test_only_the_mover_can_win() -> void:
	# 흑이 줄을 잘못 그어 백의 5목을 만들어 줬다.
	var game := _game_with("OOOOOO\n......")
	game.apply(GameState.line_action(GameState.AXIS_COL, 1))
	t.check(game.board.has_exact_five(Stone.WHITE))
	t.check_eq(game.current_player, Stone.WHITE)
	game.apply(GameState.place_action(1, 1))
	t.check_eq(game.winner, Stone.WHITE)


func test_mover_does_not_win_with_only_opponent_five() -> void:
	var game := _game_with("OOOOO.\n......", Stone.BLACK)
	game.apply(GameState.place_action(0, 1))
	t.check_eq(game.winner, Stone.EMPTY, "흑이 돌을 놓아도 백의 5목으로 백이 이기지는 않는다")
	t.check_eq(game.current_player, Stone.WHITE)


func test_state_survives_json() -> void:
	var game := GameState.new()
	game.apply(GameState.place_action(0, 0))
	game.apply(GameState.place_action(1, 0))
	var data: Dictionary = JSON.parse_string(JSON.stringify(game.to_dict()))
	t.check_eq(BoardState.from_dict(data.board).to_text(), game.board.to_text())
	t.check_eq(int(data.current_player), Stone.BLACK)


func test_json_numbers_are_accepted() -> void:
	# 네트워크로 오면 숫자가 float이 된다.
	var game := GameState.new()
	t.check(game.apply({"type": "place", "x": 1.0, "y": 2.0, "extra": true}))
	t.check_eq(game.history[0], GameState.place_action(1, 2), "정규화되어 저장된다")


func test_draw_at_turn_limit() -> void:
	var game := GameState.new()
	game.max_turns = 3
	game.apply(GameState.place_action(0, 0))
	game.apply(GameState.place_action(1, 0))
	t.check(not game.is_over())
	t.check_eq(game.turns_left(), 1)
	game.apply(GameState.place_action(2, 0))
	t.check(game.draw, "제한 수에 도달하면 무승부")
	t.check(game.is_over())
	t.check_eq(game.winner, Stone.EMPTY)
	t.check_eq(game.validate(GameState.place_action(2, 2)), "game_over")


func test_win_on_last_turn_beats_draw() -> void:
	var game := _game_with("XXXX.\n.....")
	game.max_turns = 1
	game.apply(GameState.place_action(4, 0))
	t.check_eq(game.winner, Stone.BLACK)
	t.check(not game.draw)


func test_default_turn_limit_is_450() -> void:
	t.check_eq(GameState.new().max_turns, 450)


func test_from_dict_restores_everything() -> void:
	var game := _game_with("XXXX..\n......")
	game.apply(GameState.place_action(4, 0))
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(game.to_dict())))
	t.check_eq(copy.board.to_text(), game.board.to_text())
	t.check_eq(copy.winner, Stone.BLACK)
	t.check_eq(copy.winning_line, game.winning_line)
	t.check_eq(copy.history, game.history)
	t.check_eq(copy.current_player, game.current_player)
	t.check(copy.is_over())


func test_freeze_rule_blocks_opponent_for_one_turn() -> void:
	var game := _after_opening()
	game.freeze_new_line = true
	t.check(game.apply(GameState.line_action(GameState.AXIS_COL, 2)), "흑 17수째 줄")
	t.check_eq(game.validate(GameState.place_action(2, 0)), "frozen", "백은 새 줄 위에 바로 놓을 수 없다")
	t.check(game.apply(GameState.line_action(GameState.AXIS_ROW, 4)), "백은 줄을 그을 수 있다")
	# 흑 차례: 흑의 줄(열 2)은 풀렸고, 백이 그은 줄(행 4)은 흑에게 잠겼다.
	t.check_eq(game.validate(GameState.place_action(2, 0)), "", "줄을 그은 쪽은 자기 다음 차례에 놓을 수 있다")
	t.check_eq(game.validate(GameState.place_action(0, 4)), "frozen")
	t.check(game.apply(GameState.place_action(2, 0)))
	t.check(game.frozen_line.is_empty(), "막힌 쪽이 한 수 두면 풀린다")
	t.check_eq(game.validate(GameState.place_action(0, 4)), "", "백 차례에는 행 4가 열려 있다")


func test_freeze_cut_makes_line_a_defense() -> void:
	# 백의 열린 4목을 흑이 줄로 끊으면, 빈칸이 백에게 잠겨 백이 바로 이길 수 없다.
	var game := _game_with(".OOOO..\n.......\nXX.X...")
	game.freeze_new_line = true
	game.apply(GameState.line_action(GameState.AXIS_COL, 3))
	t.check_eq(game.board.to_text().split("\n")[0], ".OO.OO..")
	t.check_eq(game.validate(GameState.place_action(3, 0)), "frozen")
	t.check(game.apply(GameState.place_action(0, 0)), "백은 다른 곳에 둔다")
	t.check_eq(game.winner, Stone.EMPTY, "양 끝에 두어도 5목이 아니다")


func test_freeze_off_by_default() -> void:
	var game := _after_opening()
	game.apply(GameState.line_action(GameState.AXIS_COL, 2))
	t.check_eq(game.validate(GameState.place_action(2, 0)), "")


func test_freeze_state_survives_json() -> void:
	var game := _after_opening()
	game.freeze_new_line = true
	game.apply(GameState.line_action(GameState.AXIS_COL, 1))
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(game.to_dict())))
	t.check(copy.freeze_new_line)
	t.check_eq(copy.validate(GameState.place_action(1, 0)), "frozen")


func test_timeout_loses_and_unlimited_turns() -> void:
	var game := GameState.new()
	game.max_turns = 0
	t.check_eq(game.turns_left(), -1, "제한 없음")
	game.apply(GameState.place_action(0, 0))
	game.timeout(Stone.WHITE)
	t.check_eq(game.winner, Stone.BLACK)
	t.check_eq(game.end_reason, "timeout")
	t.check(game.is_over())
	t.check_eq(game.validate(GameState.place_action(1, 1)), "game_over")
