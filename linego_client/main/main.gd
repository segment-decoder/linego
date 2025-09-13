# MainScene.gd

extends Control

# --- Signals ---
# (시그널 정의가 필요할 경우 여기에 작성)

# --- Enums ---
# (enum 정의가 필요할 경우 여기에 작성)

# --- Constants ---
# (상수 정의가 필요할 경우 여기에 작성)

# --- Export Variables ---
# (에디터에서 수정할 변수가 필요할 경우 여기에 작성)

# --- Onready Variables ---
@onready var matching_button: Button = $CenterContainer/PanelContainer/VBoxContainer/MatchingButton
@onready var quit_button: Button = $CenterContainer/PanelContainer/VBoxContainer/QuitButton

# --- Member Variables ---
# (일반 멤버 변수가 필요할 경우 여기에 작성)


# Godot 내장 가상 함수
func _ready() -> void:
	# 버튼의 text 속성을 코드에서 명시적으로 설정
	matching_button.text = "Matching Start"
	quit_button.text = "Quit"
	
	# 버튼의 pressed 시그널을 відповід 함수에 연결
	matching_button.pressed.connect(_on_matching_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	
	# TODO: 앱 시작 시 서버에 연결하는 로직 추가
	# WebSocketClient.connect_to_server("ws://localhost:8080")


# --- 나머지 함수 (시그널 핸들러 등) ---

# "Matching Start" 버튼이 눌렸을 때 실행될 함수
func _on_matching_button_pressed() -> void:
	print("Matching button pressed. Attempting to send 'joinQueue' request to server.")
	
	# 프로토콜에 따라 전송할 데이터(payload) 생성
	var payload: Dictionary = {
		"type": "joinQueue",
		"data": {
			"playerId": "temp_player_id_01", # 실제로는 고유 ID를 생성해야 함
			"playerName": "GodotPlayer"
		}
	}
	
	# Dictionary를 JSON 문자열로 변환
	var json_string: String = JSON.stringify(payload)
	
	# TODO: 실제 WebSocket 클라이언트를 통해 서버로 json_string 전송
	# WebSocketClient.send_message(json_string)
	
	# 중복 요청을 막기 위해 버튼을 비활성화하고 텍스트 변경
	matching_button.disabled = true
	matching_button.text = "Matching..."


# "Quit" 버튼이 눌렸을 때 실행될 함수
func _on_quit_button_pressed() -> void:
	print("Quit button pressed.")
	get_tree().quit() # 게임 애플리케이션 종료
