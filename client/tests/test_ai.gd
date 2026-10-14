extends RefCounted
## AI 전술 테스트. 두 성향 모두 같은 안전 규칙을 지켜야 한다.

const Stone := BoardState.Stone

var t  # 테스트 러너


func _game(text: String, player: int) -> GameState:
	var game := GameState.new()
	game.board = BoardState.from_text(text)
	game.current_player = player
	return game


func _for_each_style(check: Callable) -> void:
	for style in [LinegoAI.Style.AGGRESSIVE, LinegoAI.Style.DEFENSIVE]:
		check.call(LinegoAI.new(style, 7), LinegoAI.style_name(style))


func test_takes_immediate_win() -> void:
	_for_each_style(func(ai: LinegoAI, name: String):
		var game := _game("XXXX..\n......\nOOO...", Stone.BLACK)
		var action := ai.choose(game)
		t.check_eq(action, GameState.place_action(4, 0), name)
		t.check_eq(ai.last_reason, "win_place", name))


func test_does_not_make_six() -> void:
	_for_each_style(func(ai: LinegoAI, name: String):
		# (4,0)에 두면 6목이라 승리가 아니다. 이길 수 있는 곳이 없어야 한다.
		var game := _game("XXXX.X..\n........\n........", Stone.BLACK)
		t.check(LinegoAI.winning_cells(game.board, Stone.BLACK).is_empty(), name)
		t.check(ai.choose(game) != GameState.place_action(4, 0), name))


func test_blocks_opponent_four() -> void:
	_for_each_style(func(ai: LinegoAI, name: String):
		var game := _game(".OOOO...\n........\nX.X.....", Stone.BLACK)
		var action := ai.choose(game)
		t.check_eq(ai.last_reason, "block_four", name)
		t.check(action == GameState.place_action(0, 0) or action == GameState.place_action(5, 0), "%s: %s" % [name, action]))


func test_cuts_line_made_five_of_opponent() -> void:
	_for_each_style(func(ai: LinegoAI, name: String):
		var game := _game("OOOOO.\n......\nX.X...", Stone.BLACK)
		var action := ai.choose(game)
		t.check_eq(ai.last_reason, "cut_five", name)
		t.check_eq(action.type, "line", name)
		game.apply(action)
		t.check(not game.board.has_exact_five(Stone.WHITE), name))


func test_wins_with_existing_five_without_breaking_it() -> void:
	_for_each_style(func(ai: LinegoAI, name: String):
		var game := _game("XXXXX..\n.......\nOO.....", Stone.BLACK)
		var action := ai.choose(game)
		t.check_eq(ai.last_reason, "win_existing_five", name)
		game.apply(action)
		t.check_eq(game.winner, Stone.BLACK, name))


func test_splits_own_six_into_five() -> void:
	# 줄로 6목을 쪼개 5목을 만드는 수는 높게 평가되어야 한다 (상대가 끊을 수 있으면 덜 높게).
	var ai := LinegoAI.new(LinegoAI.Style.AGGRESSIVE, 1)
	var game := _game("XXXXXX.\n.......\n.......\n...O...", Stone.BLACK)
	var action := ai.choose(game)
	t.check_eq(action.type, "line", str(action))
	game.apply(action)
	t.check(game.board.has_exact_five(Stone.BLACK), "줄을 그은 뒤 흑 5목이 있어야 한다: %s" % action)


func test_does_not_open_space_for_opponent_four() -> void:
	# 백이 세로로 4개(판 높이 4). 가장자리에 가로줄을 그으면 백에게 5번째 칸을 만들어 준다.
	_for_each_style(func(ai: LinegoAI, name: String):
		for i in 20:
			ai.rng.seed = i
			var game := _game("O.X.\nO...\nO.X.\nO...", Stone.BLACK)
			var action := ai.choose(game)
			if action.type == "line":
				t.check(not LinegoAI._gives_immediate_win(game.board, action, Stone.WHITE), "%s: %s" % [name, action]))


func test_place_only_mode() -> void:
	var ai := LinegoAI.new(LinegoAI.Style.AGGRESSIVE, 3)
	ai.place_only = true
	var game := GameState.new()
	for i in 16:
		var action := ai.choose(game)
		t.check_eq(action.type, "place")
		t.check(game.apply(action))
	t.check(game.board.is_full())
	t.check_eq(game.board.width, 4)


func test_full_game_terminates() -> void:
	var game := GameState.new()
	var ais := {Stone.BLACK: LinegoAI.new(LinegoAI.Style.AGGRESSIVE, 11), Stone.WHITE: LinegoAI.new(LinegoAI.Style.DEFENSIVE, 12)}
	while not game.is_over():
		t.check(game.apply(ais[game.current_player].choose(game)), "AI는 항상 가능한 수를 둔다")
		if _current_failed_guard(game):
			break
	t.check(game.is_over())


func _current_failed_guard(game: GameState) -> bool:
	return game.turn_count() > GameState.MAX_TURNS


func test_line_delta_matches_full_rescore() -> void:
	# 최적화된 줄 평가(_line_delta)가 판 전체를 다시 센 값과 같아야 한다.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ai := LinegoAI.new()
	var mismatches := 0
	for trial in 200:
		var w := rng.randi_range(4, 12)
		var h := rng.randi_range(4, 12)
		var board := BoardState.new(w, h)
		for i in rng.randi_range(0, w * h / 2):
			board.set_stone(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1), rng.randi_range(1, 2))
		var col := rng.randf() < 0.5
		var idx := rng.randi_range(0, w if col else h)
		for color in [Stone.BLACK, Stone.WHITE]:
			ai._load(board)
			var before := ai._score_full(color)
			ai._ins_axis = 1 if col else 2
			ai._ins_idx = idx
			var after := ai._score_full(color)
			ai._ins_axis = 0
			var delta := ai._line_delta(color, col, idx)
			if absf(delta - (after - before)) > 0.001:
				mismatches += 1
				if mismatches <= 3:
					t.check(false, "%s %s idx %d: delta %f vs %f\n%s" % ["col" if col else "row", color, idx, delta, after - before, board.to_text()])
	t.check_eq(mismatches, 0)


func test_placement_delta_matches_full_rescore() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ai := LinegoAI.new()
	var mismatches := 0
	for trial in 200:
		var w := rng.randi_range(4, 12)
		var h := rng.randi_range(4, 12)
		var board := BoardState.new(w, h)
		for i in rng.randi_range(0, w * h / 2):
			board.set_stone(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1), rng.randi_range(1, 2))
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, h - 1)
		if board.get_stone(x, y) != Stone.EMPTY:
			continue
		ai._load(board)
		var before := Vector2(ai._score_full(Stone.BLACK), ai._score_full(Stone.WHITE))
		var delta := ai._placement_delta(x, y, Stone.BLACK, Stone.WHITE)
		var copy := board.duplicate_state()
		copy.set_stone(x, y, Stone.BLACK)
		ai._load(copy)
		var after := Vector2(ai._score_full(Stone.BLACK), ai._score_full(Stone.WHITE))
		# _placement_delta는 Vector2(32비트 float)로 돌려주므로 5목(100000점)이 섞이면 0.01 정도 오차가 난다.
		if (delta - (after - before)).length() > 0.05:
			mismatches += 1
	t.check_eq(mismatches, 0)


func test_freeze_ai_respects_frozen_cells() -> void:
	# 백이 이길 수 있는 유일한 칸이 백에게 잠겨 있으면 그 칸에 두지 않는다.
	_for_each_style(func(ai: LinegoAI, name: String):
		var game := _game("OO.OO..\n.......\nX.X....", Stone.WHITE)
		game.freeze_new_line = true
		game.frozen_line = {"axis": GameState.AXIS_COL, "index": 2, "blocked": Stone.WHITE}
		var action := ai.choose(game)
		t.check(game.validate(action) == "", "%s: %s" % [name, action]))


func test_freeze_ai_blocks_open_four_with_line() -> void:
	# 일반 규칙에서는 막을 수 없는 열린 4목을, 잠금 규칙에서는 줄로 끊어 막는다.
	_for_each_style(func(ai: LinegoAI, name: String):
		var game := _game("..OOOO..\n........\nX.X.X...", Stone.BLACK)
		game.freeze_new_line = true
		var action := ai.choose(game)
		t.check_eq(action.type, "line", name)
		t.check_eq(ai.last_reason, "line_block", name)
		game.apply(action)
		t.check(LinegoAI.winning_cells(game.board, Stone.WHITE).filter(func(c): return not game.is_frozen_for_current(c.x, c.y)).is_empty(), name))


func test_freeze_dead_four_split_is_an_attack() -> void:
	# 양 끝이 막힌 흑 4목을 줄로 쪼개면 빈칸이 백에게 잠겨 흑의 강한 공격이 된다.
	var ai := LinegoAI.new(LinegoAI.Style.AGGRESSIVE, 1)
	var board := BoardState.from_text("OXXXXO.\n.......\n.......\n...O...")
	var value := ai._line_attack_value(board, GameState.line_action(GameState.AXIS_COL, 3), Stone.BLACK, Stone.WHITE)
	t.check(value >= LinegoAI.LINE_ATTACK_SCORE, "줄 공격 가치 %f" % value)
