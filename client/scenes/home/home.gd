extends Control
## 홈 화면

const GAME_SCENE := "res://scenes/game/game.tscn"
const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"
const RULES_TEXT := """목표: 가로·세로·대각선으로 내 돌을 정확히 5개 이으면 승리. 6목 이상은 승리가 아닙니다.

시작: 4×4 판에서 시작합니다. 5목을 만들려면 판을 넓혀야 합니다.

내 차례에는 둘 중 하나만 합니다.
 ① 돌 놓기: 빈 교차점에 돌을 놓습니다.
 ② 줄 긋기: 줄과 줄 사이, 또는 판 바깥에 세로줄이나 가로줄을 하나 긋습니다. 그 뒤쪽 돌들이 한 칸씩 밀려 간격이 벌어집니다.

승리는 돌을 놓은 직후에만 판정합니다. 줄을 그어 5목이 생겨도 그 턴에는 이기지 않고, 다음 내 턴에 5목을 망가뜨리지 않는 곳에 돌을 놓으면 승리합니다.

두 사람의 수(돌 놓기 + 줄 긋기)를 합쳐 %d수가 되면 무승부입니다.

판 이동: 두 손가락으로 확대·축소·이동할 수 있습니다."""

@onready var easy_nav_check: CheckButton = %EasyNavCheck
@onready var rules_dialog: AcceptDialog = %RulesDialog


func _ready() -> void:
	%LocalGameButton.pressed.connect(_start_local_game)
	%OnlineGameButton.pressed.connect(get_tree().change_scene_to_file.bind(LOBBY_SCENE))
	%RulesButton.pressed.connect(rules_dialog.popup_centered)
	%QuitButton.pressed.connect(get_tree().quit)
	easy_nav_check.button_pressed = Settings.easy_navigation
	easy_nav_check.toggled.connect(func(on: bool): Settings.easy_navigation = on)
	rules_dialog.dialog_text = RULES_TEXT % GameState.MAX_TURNS


func _start_local_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
