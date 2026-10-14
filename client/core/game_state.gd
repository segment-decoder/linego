class_name GameState
extends RefCounted
## 한 판의 진행 상태와 턴 규칙. 화면/네트워크와 독립적이다.
##
## 행동(action)은 직렬화 가능한 Dictionary로 표현한다. 서버와 그대로 주고받는다.
##   돌 놓기:  {"type": "place", "x": int, "y": int}
##   줄 긋기:  {"type": "line", "axis": "col" | "row", "index": int}
##     axis "col" = 세로줄(열 추가), "row" = 가로줄(행 추가)
##     index 0 = 맨 왼쪽/위 바깥, width/height = 맨 오른쪽/아래 바깥

signal changed

const Stone := BoardState.Stone
const START_SIZE := 4
## 총 수 제한 (돌 놓기 + 줄 긋기). 도달하면 무승부. 일반 오목 최대 수(15×15=225)의 두 배.
const MAX_TURNS := 450

const AXIS_COL := "col"
const AXIS_ROW := "row"

var board: BoardState
var current_player: int = Stone.BLACK
## 0이면 승자 없음, 아니면 승자 색
var winner: int = Stone.EMPTY
## 총 수 제한에 도달해 무승부로 끝났는지
var draw := false
## 끝난 이유: "" 진행 중, "five" 5목, "turn_limit" 총 수 제한 무승부, "timeout" 시간 초과
var end_reason := ""
## 승리를 만든 5목 (Array[Vector2i])
var winning_line: Array = []
## 적용된 행동 목록 (리플레이/네트워크 동기화용)
var history: Array[Dictionary] = []
## 총 수 제한. 0이면 제한 없음 (시간 제한이 있는 대국은 시계가 끝을 정한다)
var max_turns := MAX_TURNS

## [실험 규칙] 새로 그은 줄 위에는 그 줄을 그은 사람의 상대가 바로 다음 차례에 돌을 놓을 수 없다.
var freeze_new_line := false
## 지금 잠긴 줄: {"axis", "index", "blocked": 놓을 수 없는 색}. 없으면 빈 Dictionary.
var frozen_line := {}


func _init(w: int = START_SIZE, h: int = START_SIZE) -> void:
	board = BoardState.new(w, h)


func is_over() -> bool:
	return winner != Stone.EMPTY or draw


## 오프닝: 처음 4×4 판을 돌로 모두 채울 때까지는 돌 놓기만 할 수 있다.
## (오프닝 동안은 줄을 그을 수 없으므로 판은 4×4 그대로이고, 16수를 두면 꽉 찬다)
func in_opening() -> bool:
	return board.width == START_SIZE and board.height == START_SIZE and not board.is_full()


func turn_count() -> int:
	return history.size()


## 총 수 제한까지 남은 수. 제한이 없으면 -1.
func turns_left() -> int:
	return max_turns - history.size() if max_turns > 0 else -1


## (x, y)가 지금 current_player에게 잠긴 줄 위에 있는가
func is_frozen_for_current(x: int, y: int) -> bool:
	if frozen_line.is_empty() or frozen_line.blocked != current_player:
		return false
	return x == frozen_line.index if frozen_line.axis == AXIS_COL else y == frozen_line.index


## 시간 초과로 loser가 진다.
func timeout(loser: int) -> void:
	if is_over():
		return
	winner = opponent(loser)
	end_reason = "timeout"
	changed.emit()


static func opponent(stone: int) -> int:
	return Stone.WHITE if stone == Stone.BLACK else Stone.BLACK


static func place_action(x: int, y: int) -> Dictionary:
	return {"type": "place", "x": x, "y": y}


static func line_action(axis: String, index: int) -> Dictionary:
	return {"type": "line", "axis": axis, "index": index}


## 외부(네트워크/JSON)에서 온 행동을 정규 형식으로 바꾼다. 형식이 틀리면 빈 Dictionary.
## JSON 숫자는 float로 오므로 int로 바꾸고, 불필요한 키는 버린다.
static func normalize_action(action: Variant) -> Dictionary:
	if typeof(action) != TYPE_DICTIONARY:
		return {}
	match action.get("type"):
		"place":
			if _is_number(action.get("x")) and _is_number(action.get("y")):
				return place_action(int(action.x), int(action.y))
		"line":
			if action.get("axis") in [AXIS_COL, AXIS_ROW] and _is_number(action.get("index")):
				return line_action(action.axis, int(action.index))
	return {}


static func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT]


## 행동이 지금 가능한지 검사한다. 가능하면 "" 를, 아니면 이유를 반환한다.
func validate(action: Variant) -> String:
	if is_over():
		return "game_over"
	var a := normalize_action(action)
	if a.is_empty():
		return "bad_action"
	if a.type == "place":
		if not board.is_inside(a.x, a.y):
			return "out_of_board"
		if not board.is_empty(a.x, a.y):
			return "occupied"
		if is_frozen_for_current(a.x, a.y):
			return "frozen"
		return ""
	if in_opening():
		return "opening"
	var limit := board.width if a.axis == AXIS_COL else board.height
	return "" if a.index >= 0 and a.index <= limit else "bad_index"


## 행동을 적용한다. 성공하면 true.
func apply(action: Variant) -> bool:
	if validate(action) != "":
		return false
	var a := normalize_action(action)
	var mover := current_player
	if a.type == "place":
		board.set_stone(a.x, a.y, mover)
		# 승리는 오직 돌을 놓은 직후에만 판정한다.
		# 놓은 돌이 5목에 포함될 필요는 없다: 줄긋기로 미리 만들어 둔 5목도
		# 자기 턴에 (5목을 망가뜨리지 않는) 돌을 놓으면 승리로 확정된다.
		var lines := board.find_exact_lines(mover)
		if not lines.is_empty():
			winner = mover
			winning_line = lines[0]
			end_reason = "five"
	else:
		if a.axis == AXIS_COL:
			board.insert_column(a.index)
		else:
			board.insert_row(a.index)
		# 줄긋기로 5목이 생겨도 이 턴에는 승리하지 않는다.
	history.append(a)
	# 잠긴 줄은 막힌 쪽이 한 수를 두면 풀린다. 새로 그은 줄은 상대에게 잠긴다.
	if not frozen_line.is_empty() and frozen_line.blocked == mover:
		frozen_line = {}
	if freeze_new_line and a.type == "line":
		frozen_line = {"axis": a.axis, "index": a.index, "blocked": opponent(mover)}
	# 마지막 수로 승리하면 승리가 우선한다.
	if winner == Stone.EMPTY and max_turns > 0 and history.size() >= max_turns:
		draw = true
		end_reason = "turn_limit"
	if not is_over():
		current_player = opponent(mover)
	changed.emit()
	return true


func to_dict() -> Dictionary:
	return {
		"board": board.to_dict(),
		"current_player": current_player,
		"winner": winner,
		"draw": draw,
		"winning_line": winning_line.map(func(p: Vector2i): return [p.x, p.y]),
		"history": history.duplicate(true),
		"max_turns": max_turns,
		"end_reason": end_reason,
		"freeze_new_line": freeze_new_line,
		"frozen_line": frozen_line.duplicate(),
	}


static func from_dict(data: Dictionary) -> GameState:
	var game := GameState.new()
	game.board = BoardState.from_dict(data.board)
	game.current_player = int(data.current_player)
	game.winner = int(data.winner)
	game.draw = bool(data.get("draw", false))
	game.max_turns = int(data.get("max_turns", MAX_TURNS))
	game.end_reason = str(data.get("end_reason", ""))
	game.freeze_new_line = bool(data.get("freeze_new_line", false))
	var frozen: Dictionary = data.get("frozen_line", {})
	if not frozen.is_empty():
		game.frozen_line = {"axis": str(frozen.axis), "index": int(frozen.index), "blocked": int(frozen.blocked)}
	for p in data.get("winning_line", []):
		game.winning_line.append(Vector2i(int(p[0]), int(p[1])))
	for action in data.get("history", []):
		game.history.append(normalize_action(action))
	return game
