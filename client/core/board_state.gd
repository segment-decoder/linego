class_name BoardState
extends RefCounted
## 줄긋기 오목의 판 상태. 노드에 의존하지 않는 순수 로직이라 서버/테스트에서도 그대로 쓸 수 있다.
##
## 좌표계: x = 세로줄 인덱스(0..width-1), y = 가로줄 인덱스(0..height-1).
## 돌은 교차점 (x, y)에 놓인다.

enum Stone { EMPTY = 0, BLACK = 1, WHITE = 2 }

const WIN_LENGTH := 5
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(1, 1),
	Vector2i(1, -1),
]

## 세로줄 개수
var width: int
## 가로줄 개수
var height: int
var _cells: PackedByteArray


func _init(w: int = 4, h: int = 4) -> void:
	width = w
	height = h
	_cells = PackedByteArray()
	_cells.resize(w * h)
	_cells.fill(Stone.EMPTY)


## 판 데이터 (y * width + x). AI처럼 빠른 접근이 필요한 곳에서 읽기 전용으로 쓴다.
func cells() -> PackedByteArray:
	return _cells


func is_inside(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


func get_stone(x: int, y: int) -> int:
	if not is_inside(x, y):
		return Stone.EMPTY
	return _cells[y * width + x]


func set_stone(x: int, y: int, stone: int) -> void:
	assert(is_inside(x, y))
	_cells[y * width + x] = stone


func is_empty(x: int, y: int) -> bool:
	return is_inside(x, y) and get_stone(x, y) == Stone.EMPTY


func is_full() -> bool:
	return not _cells.has(Stone.EMPTY)


## 세로줄을 index 위치에 새로 긋는다. 0이면 맨 왼쪽 바깥, width면 맨 오른쪽 바깥.
## x >= index 인 돌들은 오른쪽으로 한 칸 밀린다.
func insert_column(index: int) -> void:
	assert(index >= 0 and index <= width)
	var new_cells := PackedByteArray()
	for y in height:
		var row_start := y * width
		new_cells.append_array(_cells.slice(row_start, row_start + index))
		new_cells.append(Stone.EMPTY)
		new_cells.append_array(_cells.slice(row_start + index, row_start + width))
	width += 1
	_cells = new_cells


## 가로줄을 index 위치에 새로 긋는다. 0이면 맨 위 바깥, height면 맨 아래 바깥.
## y >= index 인 돌들은 아래로 한 칸 밀린다.
func insert_row(index: int) -> void:
	assert(index >= 0 and index <= height)
	var empty_row := PackedByteArray()
	empty_row.resize(width)
	empty_row.fill(Stone.EMPTY)
	var new_cells := _cells.slice(0, index * width)
	new_cells.append_array(empty_row)
	new_cells.append_array(_cells.slice(index * width))
	height += 1
	_cells = new_cells


## stone 색의 "정확히 5개" 연속 줄을 모두 찾는다. 6목 이상은 포함하지 않는다.
## 반환값: 각 원소가 5개의 Vector2i로 이뤄진 Array.
func find_exact_lines(stone: int, length: int = WIN_LENGTH) -> Array:
	var result := []
	for y in height:
		for x in width:
			if get_stone(x, y) != stone:
				continue
			for d in DIRECTIONS:
				# 연속 구간의 시작점에서만 센다.
				if get_stone(x - d.x, y - d.y) == stone:
					continue
				var run: Array[Vector2i] = []
				var p := Vector2i(x, y)
				while get_stone(p.x, p.y) == stone:
					run.append(p)
					p += d
				if run.size() == length:
					result.append(run)
	return result


func has_exact_five(stone: int) -> bool:
	return not find_exact_lines(stone).is_empty()


func duplicate_state() -> BoardState:
	var copy := BoardState.new(width, height)
	copy._cells = _cells.duplicate()
	return copy


func to_dict() -> Dictionary:
	return {"width": width, "height": height, "cells": Array(_cells)}


static func from_dict(data: Dictionary) -> BoardState:
	var board := BoardState.new(int(data.width), int(data.height))
	board._cells = PackedByteArray(data.cells)
	return board


## 디버그용 텍스트 표현. 테스트에서 판을 읽기 쉽게 비교할 때 쓴다.
func to_text() -> String:
	var lines := PackedStringArray()
	for y in height:
		var row := ""
		for x in width:
			row += [".", "X", "O"][get_stone(x, y)]
		lines.append(row)
	return "\n".join(lines)


## to_text()의 역변환. "." 빈칸, "X" 흑, "O" 백.
static func from_text(text: String) -> BoardState:
	var rows := text.strip_edges().split("\n")
	var board := BoardState.new(rows[0].strip_edges().length(), rows.size())
	for y in rows.size():
		var row := rows[y].strip_edges()
		for x in row.length():
			board.set_stone(x, y, ".XO".find(row[x]))
	return board
