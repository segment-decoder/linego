class_name BoardView
extends Node2D
## GameState를 그리기만 하는 노드. 입력 처리는 game.gd가 맡는다.
## 교차점 (x, y)의 로컬 좌표는 Vector2(x, y) * CELL.

const Stone := BoardState.Stone
const CELL := 96.0
const STONE_RADIUS := CELL * 0.42
const LINE_WIDTH := 3.0
## 판 바깥으로 선을 얼마나 더 그을지 (줄긋기 가능 영역을 암시)
const LINE_OVERHANG := CELL * 0.35

const COLOR_BOARD := Color("d9a95b")
const COLOR_LINE := Color("3b2a14")
const COLOR_NEW_LINE := Color("c0392b")
const COLOR_BLACK := Color("1b1b1b")
const COLOR_WHITE := Color("f4f1ea")
const COLOR_PREVIEW_LINE := Color(0.15, 0.45, 0.95, 0.9)
const COLOR_FIVE_BLACK := Color(0.95, 0.25, 0.2, 0.9)
const COLOR_FIVE_WHITE := Color(0.2, 0.55, 0.95, 0.9)

var game: GameState:
	set(value):
		if game and game.changed.is_connected(queue_redraw):
			game.changed.disconnect(queue_redraw)
		game = value
		if game:
			game.changed.connect(queue_redraw)
		queue_redraw()

## 확정 전 미리보기. GameState action 형식의 Dictionary 또는 빈 Dictionary.
var preview: Dictionary = {}:
	set(value):
		preview = value
		queue_redraw()


func intersection_position(x: int, y: int) -> Vector2:
	return Vector2(x, y) * CELL


func board_rect() -> Rect2:
	var size := Vector2(game.board.width - 1, game.board.height - 1) * CELL
	return Rect2(Vector2.ZERO, size)


## 로컬 좌표에서 가장 가까운 교차점. 판 밖이거나 너무 멀면 (-1, -1).
func intersection_at(local: Vector2) -> Vector2i:
	var cell := Vector2i((local / CELL).round())
	if not game.board.is_inside(cell.x, cell.y):
		return Vector2i(-1, -1)
	if local.distance_to(intersection_position(cell.x, cell.y)) > CELL * 0.5:
		return Vector2i(-1, -1)
	return cell


## 로컬 좌표에서 줄을 그을 위치 인덱스. 판에서 너무 멀면 -1.
## 세로줄(col): x가 i-1번 줄과 i번 줄 사이면 i. 왼쪽 바깥 0, 오른쪽 바깥 width.
func line_index_at(local: Vector2, axis: String) -> int:
	var rect := board_rect().grow(CELL * 1.5)
	if not rect.has_point(local):
		return -1
	if axis == GameState.AXIS_COL:
		return clampi(floori(local.x / CELL) + 1, 0, game.board.width)
	return clampi(floori(local.y / CELL) + 1, 0, game.board.height)


## index 위치에 새 줄을 그으면 그려질 좌표 (기존 두 줄의 한가운데).
func gap_coordinate(index: int) -> float:
	return (index - 0.5) * CELL


func _draw() -> void:
	if not game:
		return
	var board := game.board
	var rect := board_rect()
	draw_rect(rect.grow(CELL * 0.75), COLOR_BOARD)

	var last: Dictionary = game.history.back() if not game.history.is_empty() else {}
	for x in board.width:
		var color := COLOR_LINE
		if last.get("type") == "line" and last.axis == GameState.AXIS_COL and last.index == x:
			color = COLOR_NEW_LINE
		draw_line(Vector2(x * CELL, -LINE_OVERHANG), Vector2(x * CELL, rect.end.y + LINE_OVERHANG), color, LINE_WIDTH)
	for y in board.height:
		var color := COLOR_LINE
		if last.get("type") == "line" and last.axis == GameState.AXIS_ROW and last.index == y:
			color = COLOR_NEW_LINE
		draw_line(Vector2(-LINE_OVERHANG, y * CELL), Vector2(rect.end.x + LINE_OVERHANG, y * CELL), color, LINE_WIDTH)

	for y in board.height:
		for x in board.width:
			var stone := board.get_stone(x, y)
			if stone != Stone.EMPTY:
				_draw_stone(intersection_position(x, y), stone, 1.0)

	if last.get("type") == "place":
		draw_circle(intersection_position(last.x, last.y), CELL * 0.08, COLOR_NEW_LINE)

	# 판 위에 이미 완성된 5목 표시. 줄긋기로 생긴 5목은 다음 착수 때 승리로 이어지므로 경고 역할을 한다.
	for stone in [Stone.BLACK, Stone.WHITE]:
		var color := COLOR_FIVE_BLACK if stone == Stone.BLACK else COLOR_FIVE_WHITE
		for line in board.find_exact_lines(stone):
			draw_line(intersection_position(line[0].x, line[0].y), intersection_position(line[-1].x, line[-1].y), color, 10.0)

	_draw_preview(rect)


func _draw_stone(center: Vector2, stone: int, alpha: float) -> void:
	var fill := COLOR_BLACK if stone == Stone.BLACK else COLOR_WHITE
	fill.a = alpha
	draw_circle(center, STONE_RADIUS, fill)
	draw_arc(center, STONE_RADIUS, 0.0, TAU, 48, Color(0, 0, 0, 0.6 * alpha), 2.0, true)


func _draw_preview(rect: Rect2) -> void:
	match preview.get("type"):
		"place":
			_draw_stone(intersection_position(preview.x, preview.y), game.current_player, 0.5)
		"line":
			var c := gap_coordinate(preview.index)
			var from: Vector2
			var to: Vector2
			if preview.axis == GameState.AXIS_COL:
				from = Vector2(c, -LINE_OVERHANG)
				to = Vector2(c, rect.end.y + LINE_OVERHANG)
			else:
				from = Vector2(-LINE_OVERHANG, c)
				to = Vector2(rect.end.x + LINE_OVERHANG, c)
			draw_dashed_line(from, to, COLOR_PREVIEW_LINE, 6.0, 18.0)
