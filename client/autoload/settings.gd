extends Node
## 전역 설정 (autoload: Settings). user://settings.cfg 에 저장된다.

const PATH := "user://settings.cfg"

var _loading := false

## 홈 화면의 "편리한 이동" 옵션. 켜면 게임 화면에 확대/축소, 상하좌우 이동 버튼이 표시된다.
var easy_navigation := false:
	set(value):
		easy_navigation = value
		save()

## 한 기기 대전 시간 제한 (각자 5분). 끄면 총 450수 제한으로 끝난다.
var local_clock := true:
	set(value):
		local_clock = value
		save()

## 온라인 방을 만들 때 고른 시간 (분)
var online_minutes := 5:
	set(value):
		online_minutes = value
		save()

## 마지막으로 입력한 서버 주소 (예: 192.168.0.10:8080)
var server_address := "127.0.0.1:8080":
	set(value):
		server_address = value
		save()


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		_loading = true
		easy_navigation = config.get_value("ui", "easy_navigation", easy_navigation)
		server_address = config.get_value("online", "server_address", server_address)
		local_clock = config.get_value("ui", "local_clock", local_clock)
		online_minutes = config.get_value("online", "minutes", online_minutes)
		_loading = false


func save() -> void:
	if _loading:
		return
	var config := ConfigFile.new()
	config.set_value("ui", "easy_navigation", easy_navigation)
	config.set_value("online", "server_address", server_address)
	config.set_value("ui", "local_clock", local_clock)
	config.set_value("online", "minutes", online_minutes)
	config.save(PATH)
