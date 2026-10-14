extends Node
## 서버 실행 진입점 (server_main.tscn).
##   godot --headless --path client res://server/server_main.tscn -- --port=8080

## 서버는 화면이 없으니 CPU를 아끼도록 루프 속도를 제한한다.
const SERVER_FPS := 30


func _ready() -> void:
	Engine.max_fps = SERVER_FPS
	var port := LinegoServer.DEFAULT_PORT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))

	var server := LinegoServer.new()
	add_child(server)
	var err := server.start(port)
	if err != OK:
		printerr("서버를 열 수 없습니다 (port %d): %s" % [port, error_string(err)])
		get_tree().quit(1)
		return

	print("Linego 서버 실행 중 (port %d)" % port)
	print("같은 PC에서 접속:  127.0.0.1:%d" % port)
	for address in lan_addresses():
		print("같은 와이파이에서 접속:  %s:%d" % [address, port])


static func lan_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or _is_172_private(address):
			result.append(address)
	return result


static func _is_172_private(address: String) -> bool:
	if not address.begins_with("172."):
		return false
	var second := address.get_slice(".", 1).to_int()
	return second >= 16 and second <= 31
