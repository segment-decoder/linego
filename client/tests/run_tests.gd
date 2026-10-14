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
	"res://tests/test_clock.gd",
]

## 테스트 중 발생한 스크립트 오류를 잡는다. 오류로 함수가 중단되면 검사 실패가 없어도 실패로 친다.
class ErrorCatcher:
	extends Logger
	var errors: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT or error_type == ERROR_TYPE_ERROR:
			errors.append("%s (%s:%d) %s" % [rationale if rationale else code, file, line, function])

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _catcher := ErrorCatcher.new()
var failures := 0
var passed := 0
var _current_failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.add_logger(_catcher)
	for path in TEST_SCRIPTS:
		var script: Script = load(path)
		if script == null or not script.can_instantiate():
			failures += 1
			print("  FAIL  %s (스크립트를 불러올 수 없음)" % path.get_file())
			continue
		var suite: Object = script.new()
		suite.set("t", self)
		for method in suite.get_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			_current_failed = false
			_catcher.errors.clear()
			await suite.call(name)
			for error in _catcher.errors:
				_current_failed = true
				print("        script error: ", error)
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
