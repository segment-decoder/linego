extends SceneTree
## 헤드리스 테스트 러너.
##   godot --headless --path client --import          (최초 1회: 클래스 캐시 생성)
##   godot --headless --path client -s res://tests/run_tests.gd
## 실패가 있으면 종료 코드 1.

const TEST_SCRIPTS := [
	"res://tests/test_board_state.gd",
	"res://tests/test_game_state.gd",
	"res://tests/test_game_scene.gd",
	"res://tests/test_server_core.gd",
	"res://tests/test_network.gd",
	"res://tests/test_online_scene.gd",
	"res://tests/test_ai.gd",
]

var failures := 0
var passed := 0
var _current_failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path in TEST_SCRIPTS:
		var suite: Object = load(path).new()
		suite.set("t", self)
		for method in suite.get_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			_current_failed = false
			await suite.call(name)
			if _current_failed:
				failures += 1
				print("  FAIL  %s::%s" % [path.get_file(), name])
			else:
				passed += 1
				print("  ok    %s::%s" % [path.get_file(), name])
	print("\n%d passed, %d failed" % [passed, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, message: String = "") -> void:
	if not condition:
		_current_failed = true
		print("        assertion failed: ", message)


func check_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		_current_failed = true
		print("        expected %s but got %s %s" % [str(expected), str(actual), message])
