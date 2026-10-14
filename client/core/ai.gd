class_name LinegoAI
extends RefCounted
## 줄긋기 오목 AI (1수 앞 휴리스틱 + 전술 규칙).
##
## 판단 순서 (두 성향 공통):
##   1. 판에 내 5목이 있으면 그 5목을 망가뜨리지 않는 곳에 착수해 승리
##   2. 착수로 5목을 만들 수 있으면 승리
##   3. 판에 상대 5목이 있으면 그것을 끊는 줄 긋기 (유일한 방어 수단)
##   4. 상대가 다음 착수로 이길 수 있는 곳이 있으면 막기
##   5. 나머지는 평가 점수: attack × (내 점수 변화) − defense × (상대 점수 변화)
##      단, 상대에게 즉시 승리를 넘겨주는 줄 긋기(상대 4목에 빈칸을 만들어 주거나 상대 6목을 5목으로 쪼개는 줄)는 제외
## 성향은 5번의 가중치만 다르다.
##
## 점수: 5칸 창마다 한 색의 돌만 k개 있으면 WINDOW_SCORE[k]. 창 바로 바깥에 같은 색이 있으면
## 채워도 6목 이상이 되므로 0점. 판 밖 칸은 나중에 줄을 그어 생길 수 있는 빈칸으로 보되 할인한다.

enum Style { AGGRESSIVE, DEFENSIVE }

const Stone := BoardState.Stone
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
const WINDOW_SCORE: Array[float] = [0.0, 1.0, 8.0, 60.0, 500.0]
const FIVE_SCORE := 100000.0
## 상대가 줄 하나로 끊을 수 있는 5목의 가치. 상대는 반드시 줄로 끊어야 하므로(돌을 얻지 못함)
## 착수로 막아야 하는 4목(500)보다 조금 높게 본다.
const CUTTABLE_FIVE_SCORE := 800.0
## 잠금 규칙에서 상대가 줄로 되받아야 하는 줄 공격의 가치 (4목 500, 끊을 수 있는 5목 800보다 높게)
const LINE_ATTACK_SCORE := 900.0
const OUTSIDE_FACTOR := 0.6
## 착수 후보: 기존 돌에서 이 거리(체비셰프) 이내의 빈칸
const NEAR := 2
const NOISE := 2.0

const OUT := 3  # _cell()이 판 밖일 때 돌려주는 값

const STYLE_WEIGHTS := {
	Style.AGGRESSIVE: [1.0, 0.4],
	Style.DEFENSIVE: [0.4, 1.0],
}

var style: Style
var attack_weight: float
var defense_weight: float
var rng := RandomNumberGenerator.new()
## true면 돌 놓기만 한다 (실험용 오프닝 규칙)
var place_only := false
## 마지막 choose()가 어떤 이유로 수를 골랐는지 (통계용)
var last_reason := ""

# 평가 중인 판 (속도를 위해 멤버로 둔다)
var _cells: PackedByteArray
var _w := 0
var _h := 0
## 가상 줄 삽입: 0 없음, 1 세로줄(열), 2 가로줄(행)
var _ins_axis := 0
var _ins_idx := 0
## 가상 착수 (판 좌표)
var _ov_x := -999
var _ov_y := -999
var _ov_val := 0
## 돌이 있는 열/행 표시 (줄 평가에서 빈 영역을 건너뛰기 위함)
var _col_has: PackedByteArray
var _row_has: PackedByteArray


func _init(s: Style = Style.AGGRESSIVE, seed_value: int = 0) -> void:
	style = s
	attack_weight = STYLE_WEIGHTS[s][0]
	defense_weight = STYLE_WEIGHTS[s][1]
	rng.seed = seed_value


static func style_name(s: Style) -> String:
	return "aggressive" if s == Style.AGGRESSIVE else "defensive"


func choose(game: GameState) -> Dictionary:
	var board := game.board
	var me := game.current_player
	var op := GameState.opponent(me)
	var lines_allowed := not place_only and not game.in_opening()
	var freeze := game.freeze_new_line
	var legal := func(cell: Vector2i) -> bool: return not game.is_frozen_for_current(cell.x, cell.y)

	# 1. 판에 이미 내 5목 → 망가뜨리지 않는 착수로 승리
	if board.has_exact_five(me):
		for cell in _empty_cells(board):
			if not legal.call(cell):
				continue
			var copy := board.duplicate_state()
			copy.set_stone(cell.x, cell.y, me)
			if copy.has_exact_five(me):
				last_reason = "win_existing_five"
				return GameState.place_action(cell.x, cell.y)

	# 2. 착수로 5목
	var wins := winning_cells(board, me).filter(legal)
	if not wins.is_empty():
		last_reason = "win_place"
		return GameState.place_action(wins[0].x, wins[0].y)

	var candidates: Array[Dictionary] = []

	# 3. 판에 상대 5목 → 끊는 줄
	if lines_allowed and board.has_exact_five(op):
		for action in _all_line_actions(board):
			if not _after(board, action).has_exact_five(op):
				candidates.append(action)
		if not candidates.is_empty():
			last_reason = "cut_five"
			return _best(board, me, candidates)

	# 4. 상대의 착수 승리 지점 막기
	var threats := winning_cells(board, op)
	if not threats.is_empty():
		for cell in threats.filter(legal):
			candidates.append(GameState.place_action(cell.x, cell.y))
		# 기본 규칙에서 줄은 4목을 막지 못한다(끊으면 빈칸이 새 승리 지점이 됨). 그래서 착수로 다 막을 수
		# 없을 때만 줄을 본다. 잠금 규칙에서는 끊은 빈칸이 상대에게 잠기므로 줄도 수비 수단이 된다.
		if lines_allowed and (freeze or threats.size() >= 2 or candidates.is_empty()):
			var line_defenses: Array[Dictionary] = []
			for action in _line_candidates(board):
				if not _opponent_wins_after_line(board, action, op, freeze):
					line_defenses.append(action)
			# 승리 지점이 2곳 이상이면 돌 하나로는 다 막지 못하므로, 실제로 다 막는 줄만 남긴다.
			if threats.size() >= 2 and not line_defenses.is_empty():
				candidates.clear()
			candidates.append_array(line_defenses)
		if not candidates.is_empty():
			last_reason = "block_four"
			var chosen := _best(board, me, candidates)
			if chosen.type == "line":
				last_reason = "line_block"
			return chosen

	# 5. 평가 점수
	for cell in _placement_candidates(board):
		if legal.call(cell):
			candidates.append(GameState.place_action(cell.x, cell.y))
	var bonuses := {}
	if lines_allowed:
		for action in _line_candidates(board):
			if _gives_immediate_win(board, action, op, freeze):
				continue
			candidates.append(action)
			# 잠금 규칙: 새 줄 위에 내 승리 지점이 생기면 상대는 그 칸을 막을 수 없다(줄로 되받아야 함).
			if freeze:
				var bonus := _line_attack_value(board, action, me, op)
				if bonus > 0.0:
					bonuses[str(action)] = bonus
	if candidates.is_empty():
		candidates = _all_line_actions(board)
	last_reason = "heuristic"
	var chosen := _best(board, me, candidates, bonuses)
	if bonuses.has(str(chosen)):
		last_reason = "line_attack"
	return chosen


## 잠금 규칙에서, 이 줄로 새 줄 위에 내 승리 지점이 생기면 그 가치.
## 상대가 줄 하나로 되받아 모두 없앨 수 없으면 사실상 승리(FIVE_SCORE), 되받을 수 있으면 강제수 정도.
func _line_attack_value(board: BoardState, action: Dictionary, me: int, op: int) -> float:
	var after := _after(board, action)
	var on_line := _cells_on_line(winning_cells(after, me, _band_around(after, action)), action)
	if on_line.is_empty():
		return 0.0
	for counter in _all_line_actions(after):
		var after2 := _after(after, counter)
		# 상대가 되받은 줄은 이번엔 나에게 잠긴다.
		var my_wins := winning_cells(after2, me)
		if _cells_off_line(my_wins, counter).is_empty() and not after2.has_exact_five(me):
			return LINE_ATTACK_SCORE
	return FIVE_SCORE


static func _on_line(cell: Vector2i, action: Dictionary) -> bool:
	return cell.x == action.index if action.axis == GameState.AXIS_COL else cell.y == action.index


static func _cells_on_line(cells: Array[Vector2i], action: Dictionary) -> Array[Vector2i]:
	return cells.filter(func(c: Vector2i): return _on_line(c, action))


static func _cells_off_line(cells: Array[Vector2i], action: Dictionary) -> Array[Vector2i]:
	return cells.filter(func(c: Vector2i): return not _on_line(c, action))


## color가 착수 한 번으로 정확한 5목을 만들 수 있는 빈칸들. region을 주면 그 안의 돌 주변만 본다.
static func winning_cells(board: BoardState, color: int, region := Rect2i()) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var w := board.width
	var h := board.height
	var cells := board.cells()
	var seen := {}
	var x0 := 0
	var y0 := 0
	var x1 := w
	var y1 := h
	if region.has_area():
		x0 = maxi(0, region.position.x)
		y0 = maxi(0, region.position.y)
		x1 = mini(w, region.end.x)
		y1 = mini(h, region.end.y)
	for y in range(y0, y1):
		for x in range(x0, x1):
			if cells[y * w + x] != color:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h or cells[ny * w + nx] != Stone.EMPTY:
						continue
					var key := ny * w + nx
					if seen.has(key):
						continue
					seen[key] = true
					if _makes_five(cells, w, h, nx, ny, color):
						result.append(Vector2i(nx, ny))
	return result


static func _makes_five(cells: PackedByteArray, w: int, h: int, x: int, y: int, color: int) -> bool:
	for d in DIRS:
		var count := 1
		for sign in [1, -1]:
			var px: int = x + d.x * sign
			var py: int = y + d.y * sign
			while px >= 0 and py >= 0 and px < w and py < h and cells[py * w + px] == color:
				count += 1
				px += d.x * sign
				py += d.y * sign
		if count == BoardState.WIN_LENGTH:
			return true
	return false


# --- 후보 수 ------------------------------------------------------------------

func _empty_cells(board: BoardState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cells := board.cells()
	for y in board.height:
		for x in board.width:
			if cells[y * board.width + x] == Stone.EMPTY:
				result.append(Vector2i(x, y))
	return result


func _placement_candidates(board: BoardState) -> Array[Vector2i]:
	var w := board.width
	var h := board.height
	var cells := board.cells()
	var near := PackedByteArray()
	near.resize(w * h)
	var any_stone := false
	for y in h:
		for x in w:
			if cells[y * w + x] == Stone.EMPTY:
				continue
			any_stone = true
			for yy in range(maxi(0, y - NEAR), mini(h, y + NEAR + 1)):
				for xx in range(maxi(0, x - NEAR), mini(w, x + NEAR + 1)):
					near[yy * w + xx] = 1
	var result: Array[Vector2i] = []
	for y in h:
		for x in w:
			if cells[y * w + x] == Stone.EMPTY and (near[y * w + x] == 1 or not any_stone):
				result.append(Vector2i(x, y))
	return result


func _all_line_actions(board: BoardState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in board.width + 1:
		result.append(GameState.line_action(GameState.AXIS_COL, i))
	for i in board.height + 1:
		result.append(GameState.line_action(GameState.AXIS_ROW, i))
	return result


## 의미 있는 줄만: 양쪽 4칸 안에 돌이 있는 틈 + 바깥쪽 줄(판 확장) 하나씩.
func _line_candidates(board: BoardState) -> Array[Dictionary]:
	var w := board.width
	var h := board.height
	var cells := board.cells()
	var col_has := PackedByteArray()
	col_has.resize(w)
	var row_has := PackedByteArray()
	row_has.resize(h)
	for y in h:
		for x in w:
			if cells[y * w + x] != Stone.EMPTY:
				col_has[x] = 1
				row_has[y] = 1
	var result: Array[Dictionary] = []
	for i in w + 1:
		if i == 0 or i == w or (_any(col_has, i - 4, i - 1) and _any(col_has, i, i + 3)):
			result.append(GameState.line_action(GameState.AXIS_COL, i))
	for i in h + 1:
		if i == 0 or i == h or (_any(row_has, i - 4, i - 1) and _any(row_has, i, i + 3)):
			result.append(GameState.line_action(GameState.AXIS_ROW, i))
	return result


static func _any(flags: PackedByteArray, from: int, to: int) -> bool:
	for i in range(maxi(0, from), mini(flags.size(), to + 1)):
		if flags[i] == 1:
			return true
	return false


## 이 줄을 그으면 상대(op)가 다음 착수로 바로 이길 수 있게 되는가.
## 줄 전에는 상대 승리 지점/5목이 없다는 전제(choose의 5단계)에서, 바뀔 수 있는 새 줄 주변 띠만 확인한다.
## freeze(잠금 규칙)이면 새 줄 위의 칸은 상대가 다음 차례에 놓을 수 없으므로 승리 지점에서 뺀다.
static func _gives_immediate_win(board: BoardState, action: Dictionary, op: int, freeze := false) -> bool:
	var after := _after(board, action)
	var band := _band_around(after, action)
	if _has_five_in(after, op, band):
		return true
	var wins := winning_cells(after, op, band)
	if freeze:
		wins = _cells_off_line(wins, action)
	return not wins.is_empty()


## 새 줄에서 앞뒤 6칸 띠 (줄 긋기로 달라질 수 있는 연결은 모두 이 안에 걸친다)
static func _band_around(board: BoardState, action: Dictionary) -> Rect2i:
	var i: int = action.index
	if action.axis == GameState.AXIS_COL:
		return Rect2i(i - 6, 0, 13, board.height)
	return Rect2i(0, i - 6, board.width, 13)


## region 안에서 시작하는 color의 정확한 5목이 있는가
static func _has_five_in(board: BoardState, color: int, region: Rect2i) -> bool:
	var w := board.width
	var h := board.height
	var cells := board.cells()
	for y in range(maxi(0, region.position.y), mini(h, region.end.y)):
		for x in range(maxi(0, region.position.x), mini(w, region.end.x)):
			if cells[y * w + x] != color:
				continue
			for d in DIRS:
				var px := x - d.x
				var py := y - d.y
				if px >= 0 and py >= 0 and px < w and py < h and cells[py * w + px] == color:
					continue  # 연속 구간의 시작점에서만 센다
				var count := 0
				px = x
				py = y
				while px >= 0 and py >= 0 and px < w and py < h and cells[py * w + px] == color:
					count += 1
					px += d.x
					py += d.y
				if count == BoardState.WIN_LENGTH:
					return true
	return false


## 이 줄을 그은 뒤에도 상대가 다음 차례에 이길 수 있는가 (판 전체 확인 — 이미 위협이 있을 때 사용)
static func _opponent_wins_after_line(board: BoardState, action: Dictionary, op: int, freeze: bool) -> bool:
	var after := _after(board, action)
	if after.has_exact_five(op):
		return true
	var wins := winning_cells(after, op)
	if freeze:
		wins = _cells_off_line(wins, action)
	return not wins.is_empty()


## 줄 긋기를 적용한 판 복사본
static func _after(board: BoardState, action: Dictionary) -> BoardState:
	var copy := board.duplicate_state()
	if action.axis == GameState.AXIS_COL:
		copy.insert_column(action.index)
	else:
		copy.insert_row(action.index)
	return copy


# --- 평가 --------------------------------------------------------------------

func _best(board: BoardState, me: int, candidates: Array[Dictionary], bonuses := {}) -> Dictionary:
	var op := GameState.opponent(me)
	_load(board)
	var best: Dictionary = candidates[0]
	var best_value := -INF
	for action in candidates:
		var d_me: float
		var d_op: float
		if action.type == "place":
			var deltas := _placement_delta(action.x, action.y, me, op)
			d_me = deltas.x
			d_op = deltas.y
		else:
			var col: bool = action.axis == GameState.AXIS_COL
			d_me = _line_delta(me, col, action.index)
			d_op = _line_delta(op, col, action.index)
			# 줄로 내 5목이 새로 생겼는데 상대가 줄 하나로 끊을 수 있으면 가치를 낮춘다.
			if d_me > FIVE_SCORE / 2.0 and _opponent_can_cut(board, action, me):
				d_me -= FIVE_SCORE - CUTTABLE_FIVE_SCORE
		var value: float = attack_weight * (d_me + bonuses.get(str(action), 0.0)) - defense_weight * d_op + rng.randf() * NOISE
		if value > best_value:
			best_value = value
			best = action
	return best


## 줄을 그어 만든 내 5목을 상대가 줄 하나로 모두 끊을 수 있는가
func _opponent_can_cut(board: BoardState, action: Dictionary, me: int) -> bool:
	var after := _after(board, action)
	for cut in _all_line_actions(after):
		if not _after(after, cut).has_exact_five(me):
			_load(board)
			return true
	_load(board)
	return false


func _load(board: BoardState) -> void:
	_cells = board.cells()
	_w = board.width
	_h = board.height
	_ins_axis = 0
	_ov_x = -999
	_ov_y = -999
	_col_has = PackedByteArray()
	_col_has.resize(_w)
	_row_has = PackedByteArray()
	_row_has.resize(_h)
	for y in _h:
		for x in _w:
			if _cells[y * _w + x] != Stone.EMPTY:
				_col_has[x] = 1
				_row_has[y] = 1


## 줄 하나를 그었을 때 color 점수의 변화. 새 줄에 걸치거나(경계 칸 포함) 맞닿는 창만 다시 센다.
## 나머지 창은 줄 전후로 내용과 경계가 그대로라 변화가 없다.
func _line_delta(color: int, col: bool, idx: int) -> float:
	var before := 0.0
	var after := 0.0
	var other_len := _h if col else _w
	var occ := _row_has if col else _col_has
	for d in DIRS:
		var da := d.x if col else d.y
		var db := d.y if col else d.x
		if da == 0:
			continue  # 줄과 나란한 방향은 영향 없음
		for sb in range(-4, other_len + 4):
			if not _occupied(occ, sb, db):
				continue
			for sa in range(idx - 7, idx + 8):
				var lo := mini(sa - da, sa + 5 * da)
				var hi := maxi(sa - da, sa + 5 * da)
				var sx := sa if col else sb
				var sy := sb if col else sa
				if lo <= idx - 1 and hi >= idx:
					_ins_axis = 0
					before += _window(color, sx, sy, d.x, d.y)
				if lo <= idx and hi >= idx:
					_ins_axis = 1 if col else 2
					_ins_idx = idx
					after += _window(color, sx, sy, d.x, d.y)
	_ins_axis = 0
	return after - before


## 창이 지나는 (줄과 나란한 축의) 줄들 중 돌이 있는 줄이 있는가
static func _occupied(occ: PackedByteArray, start: int, step: int) -> bool:
	for k in 5:
		var i := start + k * step
		if i >= 0 and i < occ.size() and occ[i] == 1:
			return true
	return false


## 가상 판(줄 삽입/가상 착수 반영) 좌표의 칸 값
func _cell(x: int, y: int) -> int:
	if x == _ov_x and y == _ov_y:
		return _ov_val
	if _ins_axis == 1:
		if x == _ins_idx:
			return Stone.EMPTY if y >= 0 and y < _h else OUT
		if x > _ins_idx:
			x -= 1
	elif _ins_axis == 2:
		if y == _ins_idx:
			return Stone.EMPTY if x >= 0 and x < _w else OUT
		if y > _ins_idx:
			y -= 1
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return OUT
	return _cells[y * _w + x]


func _window(color: int, sx: int, sy: int, dx: int, dy: int) -> float:
	var k := 0
	var outside := false
	for i in 5:
		var v := _cell(sx + i * dx, sy + i * dy)
		if v == color:
			k += 1
		elif v == OUT:
			outside = true
		elif v != Stone.EMPTY:
			return 0.0
	if k == 0:
		return 0.0
	if _cell(sx - dx, sy - dy) == color or _cell(sx + 5 * dx, sy + 5 * dy) == color:
		return 0.0
	if k == 5:
		return FIVE_SCORE
	return WINDOW_SCORE[k] * (OUTSIDE_FACTOR if outside else 1.0)


## 현재 가상 판에서 color의 전체 점수. 창은 그 안의 첫 번째 color 돌에서만 센다(중복 방지).
func _score_full(color: int) -> float:
	var total := 0.0
	for oy in _h:
		for ox in _w:
			if _cells[oy * _w + ox] != color:
				continue
			var x := ox
			var y := oy
			if _ins_axis == 1 and ox >= _ins_idx:
				x += 1
			elif _ins_axis == 2 and oy >= _ins_idx:
				y += 1
			for d in DIRS:
				for o in 5:
					var sx := x - o * d.x
					var sy := y - o * d.y
					var first := true
					for i in o:
						if _cell(sx + i * d.x, sy + i * d.y) == color:
							first = false
							break
					if first:
						total += _window(color, sx, sy, d.x, d.y)
	return total


## (x, y)에 me가 착수할 때 (내 점수 변화, 상대 점수 변화). 그 칸을 포함하거나 경계로 두는 창만 다시 센다.
func _placement_delta(x: int, y: int, me: int, op: int) -> Vector2:
	var d_me := 0.0
	var d_op := 0.0
	for d in DIRS:
		for o in range(-1, 6):
			var sx := x - o * d.x
			var sy := y - o * d.y
			_ov_x = -999
			var before_me := _window(me, sx, sy, d.x, d.y)
			var before_op := _window(op, sx, sy, d.x, d.y)
			_ov_x = x
			_ov_y = y
			_ov_val = me
			d_me += _window(me, sx, sy, d.x, d.y) - before_me
			d_op += _window(op, sx, sy, d.x, d.y) - before_op
	_ov_x = -999
	return Vector2(d_me, d_op)
