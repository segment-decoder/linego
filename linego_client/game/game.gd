extends Node2D

var	board_size_x = 3
var	board_size_y = 3

var	board = []

func	_ready():
	init_board()
	print_board()

func	init_board():
	board.clear()
	for y in range(board_size_y):
		var	row = []
		for x in range(board_size_x):
			row.append(0)
		board.append(row)

func	print_board():
	for row in board:
		print(row)
