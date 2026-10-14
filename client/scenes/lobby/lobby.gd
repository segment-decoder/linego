extends Control
## 온라인 로비: 서버 주소 입력, 방 만들기 / 방 코드로 참가.

const HOME_SCENE := "res://scenes/home/home.tscn"
const GAME_SCENE := "res://scenes/game/game.tscn"

const ERROR_TEXT := {
	"no_such_room": "그런 방이 없습니다. 코드를 확인하세요.",
	"room_full": "이미 두 명이 들어간 방입니다.",
	"version_mismatch": "서버와 게임 버전이 다릅니다. 게임을 업데이트하세요.",
}

## 연결된 뒤 보낼 요청 (연결 전에 버튼을 누른 경우)
var _pending_request := {}

@onready var address_edit: LineEdit = %AddressEdit
@onready var code_edit: LineEdit = %CodeEdit
@onready var status_label: Label = %StatusLabel
@onready var create_button: Button = %CreateButton
@onready var join_button: Button = %JoinButton


func _ready() -> void:
	address_edit.text = Settings.server_address
	var time_option: OptionButton = %TimeOption
	for minutes in ChessClock.ALLOWED_MINUTES:
		time_option.add_item("%d분" % minutes, minutes)
	time_option.select(maxi(0, ChessClock.ALLOWED_MINUTES.find(Settings.online_minutes)))
	time_option.item_selected.connect(func(i: int): Settings.online_minutes = time_option.get_item_id(i))
	create_button.pressed.connect(func(): _request({"t": "create_room", "minutes": Settings.online_minutes}))
	join_button.pressed.connect(_on_join_pressed)
	code_edit.text_submitted.connect(func(_text): _on_join_pressed())
	%BackButton.pressed.connect(_go_home)
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_connection_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.message_received.connect(_on_message)
	status_label.text = "친구와 같은 서버 주소를 입력하고, 한 명은 방을 만들고 다른 한 명은 코드로 참가하세요."


func _on_join_pressed() -> void:
	var code := code_edit.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = "방 코드를 입력하세요."
		return
	_request({"t": "join_room", "code": code})


func _request(msg: Dictionary) -> void:
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		status_label.text = "서버 주소를 입력하세요."
		return
	Settings.server_address = address
	if Net.is_open():
		Net.send(msg)
		return
	_pending_request = msg
	if Net.connect_to_server(address) != OK:
		status_label.text = "서버 주소가 올바르지 않습니다."
		return
	status_label.text = "서버에 연결하는 중..."
	_set_busy(true)


func _on_connected() -> void:
	_set_busy(false)
	if not _pending_request.is_empty():
		Net.send(_pending_request)
		_pending_request = {}


func _on_connection_failed() -> void:
	_set_busy(false)
	_pending_request = {}
	status_label.text = "서버에 연결할 수 없습니다.\n주소와 포트, 서버 실행 여부, 같은 와이파이인지 확인하세요."


func _on_disconnected() -> void:
	_set_busy(false)
	status_label.text = "서버와 연결이 끊어졌습니다."


func _on_message(msg: Dictionary) -> void:
	match msg.get("t"):
		"room_created":
			status_label.text = "방 코드:  %s   (각자 %d분)\n\n친구가 이 코드로 참가하면 게임이 시작됩니다." % [msg.code, int(msg.get("minutes", 5))]
		"game_start":
			get_tree().change_scene_to_file(GAME_SCENE)
		"opponent_left":
			status_label.text = "상대가 나갔습니다."
		"error":
			status_label.text = ERROR_TEXT.get(msg.get("reason"), "오류: %s" % msg.get("reason"))


func _set_busy(busy: bool) -> void:
	create_button.disabled = busy
	join_button.disabled = busy


func _go_home() -> void:
	Net.close()
	get_tree().change_scene_to_file(HOME_SCENE)
