extends RefCounted

const Stone := BoardState.Stone

var t  # 테스트 러너


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
	t.check(game.apply(GameState.line_action(GameState.AXIS_COL, 4)))
	t.check_eq(game.current_player, Stone.BLACK)
	t.check_eq(game.board.width, 5)
	t.check_eq(game.history.size(), 2)


func test_invalid_actions_are_rejected() -> void:
	var game := GameState.new()
	game.apply(GameState.place_action(1, 1))
	t.check_eq(game.validate(GameState.place_action(1, 1)), "occupied")
	t.check_eq(game.validate(GameState.place_action(4, 0)), "out_of_board")
	t.check_eq(game.validate(GameState.line_action(GameState.AXIS_COL, 5)), "bad_index")
	t.check_eq(game.validate(GameState.line_action(GameState.AXIS_ROW, -1)), "bad_index")
	t.check_eq(game.validate(GameState.line_action("diag", 0)), "bad_axis")
	t.check_eq(game.validate({"type": "pass"}), "bad_type")
	t.check(not game.apply(GameState.place_action(1, 1)))
	t.check_eq(game.current_player, Stone.WHITE, "실패한 행동은 턴을 넘기지 않는다")


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
	game.apply(GameState.line_action(GameState.AXIS_ROW, 0))
	var data: Dictionary = JSON.parse_string(JSON.stringify(game.to_dict()))
	t.check_eq(BoardState.from_dict(data.board).to_text(), game.board.to_text())
	t.check_eq(int(data.current_player), Stone.BLACK)
