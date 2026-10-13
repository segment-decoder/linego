class_name GameState
extends RefCounted
## 한 판의 진행 상태와 턴 규칙. 화면/네트워크와 독립적이다.
##
## 행동(action)은 직렬화 가능한 Dictionary로 표현한다. 나중에 서버와 그대로 주고받을 수 있다.
##   돌 놓기:  {"type": "place", "x": int, "y": int}
##   줄 긋기:  {"type": "line", "axis": "col" | "row", "index": int}
##     axis "col" = 세로줄(열 추가), "row" = 가로줄(행 추가)
##     index 0 = 맨 왼쪽/위 바깥, width/height = 맨 오른쪽/아래 바깥

signal changed

const Stone := BoardState.Stone
const START_SIZE := 4

const AXIS_COL := "col"
const AXIS_ROW := "row"

var board: BoardState
var current_player: int = Stone.BLACK
## 0이면 진행 중, 아니면 승자 색
var winner: int = Stone.EMPTY
## 승리를 만든 5목 (Array[Vector2i])
var winning_line: Array = []
## 적용된 행동 목록 (리플레이/네트워크 동기화용)
var history: Array[Dictionary] = []


func _init(w: int = START_SIZE, h: int = START_SIZE) -> void:
	board = BoardState.new(w, h)


func is_over() -> bool:
	return winner != Stone.EMPTY


static func opponent(stone: int) -> int:
	return Stone.WHITE if stone == Stone.BLACK else Stone.BLACK


static func place_action(x: int, y: int) -> Dictionary:
	return {"type": "place", "x": x, "y": y}


static func line_action(axis: String, index: int) -> Dictionary:
	return {"type": "line", "axis": axis, "index": index}


## 행동이 지금 가능한지 검사한다. 가능하면 "" 를, 아니면 이유를 반환한다.
func validate(action: Dictionary) -> String:
	if is_over():
		return "game_over"
	match action.get("type"):
		"place":
			var x := int(action.get("x", -1))
			var y := int(action.get("y", -1))
			if not board.is_inside(x, y):
				return "out_of_board"
			if not board.is_empty(x, y):
				return "occupied"
			return ""
		"line":
			var index := int(action.get("index", -1))
			match action.get("axis"):
				AXIS_COL:
					return "" if index >= 0 and index <= board.width else "bad_index"
				AXIS_ROW:
					return "" if index >= 0 and index <= board.height else "bad_index"
				_:
					return "bad_axis"
		_:
			return "bad_type"


## 행동을 적용한다. 성공하면 true.
func apply(action: Dictionary) -> bool:
	if validate(action) != "":
		return false
	var mover := current_player
	if action.type == "place":
		board.set_stone(int(action.x), int(action.y), mover)
		# 승리는 오직 돌을 놓은 직후에만 판정한다.
		# 놓은 돌이 5목에 포함될 필요는 없다: 줄긋기로 미리 만들어 둔 5목도
		# 자기 턴에 (5목을 망가뜨리지 않는) 돌을 놓으면 승리로 확정된다.
		var lines := board.find_exact_lines(mover)
		if not lines.is_empty():
			winner = mover
			winning_line = lines[0]
	else:
		if action.axis == AXIS_COL:
			board.insert_column(int(action.index))
		else:
			board.insert_row(int(action.index))
		# 줄긋기로 5목이 생겨도 이 턴에는 승리하지 않는다.
	history.append(action.duplicate())
	if not is_over():
		current_player = opponent(mover)
	changed.emit()
	return true


func to_dict() -> Dictionary:
	return {
		"board": board.to_dict(),
		"current_player": current_player,
		"winner": winner,
		"history": history.duplicate(true),
	}
