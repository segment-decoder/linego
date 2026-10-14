class_name ChessClock
extends RefCounted
## 대국 시계 (총 시간제, 추가 시간 없음). 자기 차례에만 자기 시간이 줄고, 0이 되면 진다.
## 추가 시간(피셔)이나 지연 방식은 빠른 '의미 없는 수'로 시간을 벌 수 있어서 쓰지 않는다.
## 시각은 호출하는 쪽이 밀리초로 넘긴다 (서버/클라이언트/테스트가 각자의 시계를 쓸 수 있게).

const Stone := BoardState.Stone
const DEFAULT_MINUTES := 10
const ALLOWED_MINUTES: Array[int] = [5, 10, 20]

var minutes: int
## 각 색의 남은 시간 (마지막으로 정산한 시점 기준)
var remaining_ms := {}
## 지금 시간이 흐르는 색. 0이면 멈춤.
var running := 0
var _since_ms := 0


func _init(minutes_each: int = DEFAULT_MINUTES) -> void:
	minutes = minutes_each
	remaining_ms = {Stone.BLACK: minutes_each * 60000, Stone.WHITE: minutes_each * 60000}


func start(color: int, now_ms: int) -> void:
	running = color
	_since_ms = now_ms


## 지금 흐르는 쪽의 시간을 정산하고 color의 시간을 흐르게 한다. color가 0이면 멈춘다.
func switch_to(color: int, now_ms: int) -> void:
	if running != 0:
		remaining_ms[running] = remaining(running, now_ms)
	running = color
	_since_ms = now_ms


func stop(now_ms: int) -> void:
	switch_to(0, now_ms)


func remaining(color: int, now_ms: int) -> int:
	var ms: int = remaining_ms[color]
	if color == running:
		ms -= now_ms - _since_ms
	return maxi(0, ms)


## 시간이 다 떨어진 색 (흐르는 쪽만 떨어질 수 있다). 없으면 0.
func flagged(now_ms: int) -> int:
	if running != 0 and remaining(running, now_ms) <= 0:
		return running
	return 0


func to_dict(now_ms: int) -> Dictionary:
	return {
		"minutes": minutes,
		"black_ms": remaining(Stone.BLACK, now_ms),
		"white_ms": remaining(Stone.WHITE, now_ms),
		"running": running,
	}


## 서버가 보낸 상태로 맞춘다. now_ms는 받는 쪽의 현재 시각.
static func from_dict(data: Dictionary, now_ms: int) -> ChessClock:
	var clock := ChessClock.new(int(data.get("minutes", DEFAULT_MINUTES)))
	clock.remaining_ms = {Stone.BLACK: int(data.black_ms), Stone.WHITE: int(data.white_ms)}
	clock.start(int(data.running), now_ms)
	return clock


static func format(ms: int) -> String:
	var seconds := ceili(ms / 1000.0)
	return "%d:%02d" % [seconds / 60, seconds % 60]
