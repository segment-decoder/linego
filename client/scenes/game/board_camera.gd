class_name BoardCamera
extends Camera2D
## 판을 보는 카메라. 제스처 해석은 game.gd가 하고, 여기서는 이동/확대 연산만 한다.

const MIN_ZOOM := 0.15
const MAX_ZOOM := 3.0

## 카메라가 판에서 너무 멀어지지 않도록 제한할 영역 (월드 좌표)
var limit_rect := Rect2()


func screen_to_world(screen: Vector2) -> Vector2:
	return (screen - get_viewport_rect().size / 2.0) / zoom.x + position


## 월드 좌표 world가 화면 좌표 screen에 보이도록 카메라를 옮긴다.
func put_world_at_screen(world: Vector2, screen: Vector2) -> void:
	position = world - (screen - get_viewport_rect().size / 2.0) / zoom.x
	_clamp_position()


func pan_screen(screen_delta: Vector2) -> void:
	position -= screen_delta / zoom.x
	_clamp_position()


## screen 지점을 고정한 채 factor 배 확대한다.
func zoom_at(screen: Vector2, factor: float) -> void:
	var anchor := screen_to_world(screen)
	var z := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	put_world_at_screen(anchor, screen)


## world_rect 전체가 화면의 view_rect 영역 안에 들어오도록 맞춘다.
func fit(world_rect: Rect2, view_rect: Rect2) -> void:
	var z := minf(view_rect.size.x / world_rect.size.x, view_rect.size.y / world_rect.size.y)
	z = clampf(z, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	put_world_at_screen(world_rect.get_center(), view_rect.get_center())


func _clamp_position() -> void:
	if limit_rect.has_area():
		position = position.clamp(limit_rect.position, limit_rect.end)
