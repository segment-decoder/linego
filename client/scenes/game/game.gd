extends Node2D
## 게임 화면 (한 기기 2인 대전). 입력 해석과 UI 갱신을 맡고, 규칙은 GameState에 위임한다.

enum Mode { PLACE, LINE_COL, LINE_ROW }

const Stone := BoardState.Stone
const HOME_SCENE := "res://scenes/home/home.tscn"
## 이 거리(px) 이상 움직이면 탭이 아니라 드래그로 본다.
const TAP_SLOP := 24.0
## 편리한 이동 버튼 한 번에 움직일 칸 수
const NAV_STEP_CELLS := 3
const NAV_ZOOM_FACTOR := 1.25
const WHEEL_ZOOM_FACTOR := 1.1

var game: GameState
var mode := Mode.PLACE

## 현재 판 위에 있는 손가락들: index -> 화면 좌표
var _touches := {}
var _tap_index := -1
var _tap_start := Vector2.ZERO

@onready var board_view: BoardView = $BoardView
@onready var camera: BoardCamera = $Camera
@onready var board_area: Control = %BoardArea
@onready var turn_label: Label = %TurnLabel
@onready var hint_label: Label = %HintLabel
@onready var place_button: Button = %PlaceButton
@onready var col_button: Button = %ColButton
@onready var row_button: Button = %RowButton
@onready var confirm_button: Button = %ConfirmButton
@onready var nav_pad: Control = %NavPad
@onready var result_panel: Control = %ResultPanel
@onready var result_label: Label = %ResultLabel


func _ready() -> void:
	var group := ButtonGroup.new()
	for button in [place_button, col_button, row_button]:
		button.toggle_mode = true
		button.button_group = group
	place_button.pressed.connect(_set_mode.bind(Mode.PLACE))
	col_button.pressed.connect(_set_mode.bind(Mode.LINE_COL))
	row_button.pressed.connect(_set_mode.bind(Mode.LINE_ROW))
	confirm_button.pressed.connect(_confirm_preview)
	%FitButton.pressed.connect(fit_camera)
	%HomeButton.pressed.connect(_go_home)
	%ResultHomeButton.pressed.connect(_go_home)
	%RematchButton.pressed.connect(new_game)

	%ZoomInButton.pressed.connect(func(): camera.zoom_at(board_area.get_global_rect().get_center(), NAV_ZOOM_FACTOR))
	%ZoomOutButton.pressed.connect(func(): camera.zoom_at(board_area.get_global_rect().get_center(), 1.0 / NAV_ZOOM_FACTOR))
	%UpButton.pressed.connect(_nav_move.bind(Vector2.UP))
	%DownButton.pressed.connect(_nav_move.bind(Vector2.DOWN))
	%LeftButton.pressed.connect(_nav_move.bind(Vector2.LEFT))
	%RightButton.pressed.connect(_nav_move.bind(Vector2.RIGHT))
	nav_pad.visible = Settings.easy_navigation

	new_game()


func new_game() -> void:
	game = GameState.new()
	board_view.game = game
	board_view.preview = {}
	result_panel.hide()
	_set_mode(Mode.PLACE)
	_update_camera_limits()
	# 컨테이너 배치가 끝난 뒤에 BoardArea 크기를 알 수 있다.
	fit_camera.call_deferred()


func fit_camera() -> void:
	camera.fit(board_view.board_rect().grow(BoardView.CELL), board_area.get_global_rect())


# --- 입력 ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_screen_touch(event)
	elif event is InputEventScreenDrag:
		_on_screen_drag(event)
	elif event is InputEventMouseButton and event.pressed and _in_board_area(event.position):
		# 데스크톱 테스트용 휠 확대/축소
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom_at(event.position, WHEEL_ZOOM_FACTOR)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom_at(event.position, 1.0 / WHEEL_ZOOM_FACTOR)
	elif event is InputEventMagnifyGesture and _in_board_area(event.position):
		camera.zoom_at(event.position, event.factor)


func _on_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# 첫 손가락은 판 영역 안에서 시작해야 한다 (상/하단 UI 터치와 구분).
		if _touches.is_empty() and not _in_board_area(event.position):
			return
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_tap_index = event.index
			_tap_start = event.position
		else:
			_tap_index = -1  # 두 손가락 이상이면 탭이 아니다.
	elif _touches.has(event.index):
		if event.index == _tap_index and _touches.size() == 1:
			handle_tap(event.position)
		_touches.erase(event.index)
		if _touches.is_empty():
			_tap_index = -1


func _on_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	var old_touches := _touches.duplicate()
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		# 두 손가락: 두 점의 중심 이동 = 화면 이동, 두 점 사이 거리 변화 = 확대/축소
		var keys := _touches.keys().slice(0, 2)
		var old_a: Vector2 = old_touches[keys[0]]
		var old_b: Vector2 = old_touches[keys[1]]
		var new_a: Vector2 = _touches[keys[0]]
		var new_b: Vector2 = _touches[keys[1]]
		var old_dist := old_a.distance_to(old_b)
		if old_dist < 1.0:
			return
		var anchor := camera.screen_to_world((old_a + old_b) / 2.0)
		camera.zoom_at((old_a + old_b) / 2.0, new_a.distance_to(new_b) / old_dist)
		camera.put_world_at_screen(anchor, (new_a + new_b) / 2.0)
	else:
		# 한 손가락: 조금 이상 움직이면 탭을 취소하고 화면을 끈다.
		if _tap_index == event.index and event.position.distance_to(_tap_start) > TAP_SLOP:
			_tap_index = -1
		if _tap_index == -1:
			camera.pan_screen(event.position - old_touches[event.index])


func _in_board_area(screen: Vector2) -> bool:
	return board_area.get_global_rect().has_point(screen) and not result_panel.visible


## 판 위를 탭했을 때. 첫 탭은 미리보기, 같은 곳을 한 번 더 탭하면 확정.
func handle_tap(screen: Vector2) -> void:
	if game.is_over():
		return
	var local := board_view.to_local(camera.screen_to_world(screen))
	var action := {}
	match mode:
		Mode.PLACE:
			var cell := board_view.intersection_at(local)
			if cell.x >= 0:
				action = GameState.place_action(cell.x, cell.y)
		Mode.LINE_COL, Mode.LINE_ROW:
			var axis := GameState.AXIS_COL if mode == Mode.LINE_COL else GameState.AXIS_ROW
			var index := board_view.line_index_at(local, axis)
			if index >= 0:
				action = GameState.line_action(axis, index)

	if action.is_empty() or game.validate(action) != "":
		board_view.preview = {}
	elif action == board_view.preview:
		_confirm_preview()
		return
	else:
		board_view.preview = action
	_update_ui()


# --- 행동 적용 -------------------------------------------------------------

func _confirm_preview() -> void:
	if board_view.preview.is_empty():
		return
	apply_action(board_view.preview)


func apply_action(action: Dictionary) -> bool:
	if action.type == "line":
		_keep_view_stable_for_line(action)
	if not game.apply(action):
		return false
	board_view.preview = {}
	_update_camera_limits()
	_set_mode(Mode.PLACE)
	if game.is_over():
		_show_result()
	return true


## 줄을 그으면 그 뒤쪽 돌들이 한 칸씩 밀린다. 보고 있던 곳이 밀린 쪽이면 카메라도 같이 옮겨
## 화면이 튀지 않게 한다.
func _keep_view_stable_for_line(action: Dictionary) -> void:
	var gap := board_view.gap_coordinate(action.index)
	if action.axis == GameState.AXIS_COL and camera.position.x > gap:
		camera.position.x += BoardView.CELL
	elif action.axis == GameState.AXIS_ROW and camera.position.y > gap:
		camera.position.y += BoardView.CELL


func _update_camera_limits() -> void:
	camera.limit_rect = board_view.board_rect().grow(BoardView.CELL * 3)


func _nav_move(direction: Vector2) -> void:
	camera.position += direction * BoardView.CELL * NAV_STEP_CELLS
	camera.pan_screen(Vector2.ZERO)  # 이동 제한 적용


func _go_home() -> void:
	get_tree().change_scene_to_file(HOME_SCENE)


# --- UI ------------------------------------------------------------------

func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	place_button.button_pressed = mode == Mode.PLACE
	col_button.button_pressed = mode == Mode.LINE_COL
	row_button.button_pressed = mode == Mode.LINE_ROW
	board_view.preview = {}
	_update_ui()


static func stone_name(stone: int) -> String:
	return "흑" if stone == Stone.BLACK else "백"


func _update_ui() -> void:
	var board := game.board
	turn_label.text = "%s 차례  ·  판 %d×%d" % [stone_name(game.current_player), board.width, board.height]
	confirm_button.disabled = board_view.preview.is_empty()

	var hint := ""
	match mode:
		Mode.PLACE:
			hint = "교차점을 눌러 돌을 놓을 곳을 고르세요."
		Mode.LINE_COL:
			hint = "세로줄을 그을 위치(줄 사이 또는 바깥)를 누르세요."
		Mode.LINE_ROW:
			hint = "가로줄을 그을 위치(줄 사이 또는 바깥)를 누르세요."
	if not board_view.preview.is_empty():
		hint = "같은 곳을 한 번 더 누르거나 [확정]을 누르세요."

	var me := game.current_player
	var other := GameState.opponent(me)
	if board.has_exact_five(other):
		hint += "\n%s의 5목이 판에 있습니다! 줄을 그어 끊지 않으면 다음 착수에 집니다." % stone_name(other)
	elif board.has_exact_five(me):
		hint += "\n5목 완성 상태입니다. 5목을 망가뜨리지 않는 곳에 돌을 놓으면 승리!"
	hint_label.text = hint


func _show_result() -> void:
	result_label.text = "%s 승리!" % stone_name(game.winner)
	turn_label.text = "게임 종료"
	confirm_button.disabled = true
	result_panel.show()
