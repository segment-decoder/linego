extends SceneTree
## AI 자동 대국 실험.
##   godot --headless --path client -s res://tools/simulate.gd -- --experiment=1 --games=100 --seed=1 --out=/tmp/exp1.jsonl
##
## 실험:
##   1 두 플레이어 모두 공격형
##   2 두 플레이어 모두 방어형
##   3 매 판 각자 무작위 성향
##   4 처음 4×4 16칸을 모두 채울 때까지 돌 놓기만, 성향은 매 판 각자 무작위
## 결과는 한 판에 한 줄씩 JSON (JSON Lines).

const Stone := BoardState.Stone
const OPENING_FILL_TURNS := GameState.START_SIZE * GameState.START_SIZE


func _initialize() -> void:
	var args := {"experiment": "1", "games": "10", "seed": "1", "out": ""}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			args[arg.substr(2, arg.find("=") - 2)] = arg.get_slice("=", 1)
	var experiment := int(args.experiment)
	var games := int(args.games)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(args.seed)
	var out: FileAccess = FileAccess.open(args.out, FileAccess.WRITE) if args.out != "" else null

	for i in games:
		var styles := _styles_for(experiment, rng)
		var record := play(experiment, styles[0], styles[1], rng.randi())
		record["game"] = i
		var line := JSON.stringify(record)
		if out:
			out.store_line(line)
			out.flush()
		else:
			print(line)
	quit()


func _styles_for(experiment: int, rng: RandomNumberGenerator) -> Array:
	match experiment:
		1:
			return [LinegoAI.Style.AGGRESSIVE, LinegoAI.Style.AGGRESSIVE]
		2:
			return [LinegoAI.Style.DEFENSIVE, LinegoAI.Style.DEFENSIVE]
		_:
			return [rng.randi_range(0, 1), rng.randi_range(0, 1)]


static func play(experiment: int, black_style: int, white_style: int, seed_value: int) -> Dictionary:
	var started := Time.get_ticks_msec()
	var game := GameState.new()
	var ais := {
		Stone.BLACK: LinegoAI.new(black_style, seed_value),
		Stone.WHITE: LinegoAI.new(white_style, seed_value + 1),
	}
	var stats := {
		Stone.BLACK: {"places": 0, "lines": 0, "line_fives": 0, "cuts": 0, "blocks": 0},
		Stone.WHITE: {"places": 0, "lines": 0, "line_fives": 0, "cuts": 0, "blocks": 0},
	}
	var first_line_turn := -1
	var win_kind := ""
	while not game.is_over():
		var mover := game.current_player
		var ai: LinegoAI = ais[mover]
		ai.place_only = experiment == 4 and game.turn_count() < OPENING_FILL_TURNS
		var action := ai.choose(game)
		var had_five := game.board.has_exact_five(mover)
		if not game.apply(action):
			push_error("AI가 잘못된 수를 골랐습니다: %s" % action)
			break
		var s: Dictionary = stats[mover]
		if action.type == "place":
			s.places += 1
		else:
			s.lines += 1
			if first_line_turn < 0:
				first_line_turn = game.turn_count()
			if not had_five and game.board.has_exact_five(mover):
				s.line_fives += 1
		match ai.last_reason:
			"cut_five":
				s.cuts += 1
			"block_four":
				s.blocks += 1
		if game.winner != Stone.EMPTY:
			# 줄로 미리 만든 5목으로 이겼는지, 착수로 5목을 완성했는지
			win_kind = "line_five" if ai.last_reason == "win_existing_five" else "placement"

	return {
		"experiment": experiment,
		"black": LinegoAI.style_name(black_style),
		"white": LinegoAI.style_name(white_style),
		"winner": "black" if game.winner == Stone.BLACK else "white" if game.winner == Stone.WHITE else "draw",
		"win_kind": win_kind,
		"turns": game.turn_count(),
		"first_line_turn": first_line_turn,
		"width": game.board.width,
		"height": game.board.height,
		"black_stats": stats[Stone.BLACK],
		"white_stats": stats[Stone.WHITE],
		"ms": Time.get_ticks_msec() - started,
	}
