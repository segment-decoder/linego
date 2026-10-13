extends Node
## 전역 설정 (autoload: Settings). user://settings.cfg 에 저장된다.

const PATH := "user://settings.cfg"

## 홈 화면의 "편리한 이동" 옵션. 켜면 게임 화면에 확대/축소, 상하좌우 이동 버튼이 표시된다.
var easy_navigation := false:
	set(value):
		easy_navigation = value
		save()


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		easy_navigation = config.get_value("ui", "easy_navigation", false)


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("ui", "easy_navigation", easy_navigation)
	config.save(PATH)
