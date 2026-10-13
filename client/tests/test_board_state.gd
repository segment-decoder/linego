extends RefCounted

const Stone := BoardState.Stone

var t  # 테스트 러너


func test_starts_empty_4x4() -> void:
	var board := BoardState.new()
	t.check_eq(board.width, 4)
	t.check_eq(board.height, 4)
	t.check_eq(board.to_text(), "....\n....\n....\n....")


func test_insert_column_between_lines_shifts_right_side() -> void:
	var board := BoardState.from_text("""
		X..O
		.XO.
	""")
	board.insert_column(2)
	t.check_eq(board.width, 5)
	t.check_eq(board.to_text(), "X...O\n.X.O.")


func test_insert_column_at_edges() -> void:
	var board := BoardState.from_text("XO")
	board.insert_column(0)
	t.check_eq(board.to_text(), ".XO")
	board.insert_column(3)
	t.check_eq(board.to_text(), ".XO.")


func test_insert_row_between_and_edges() -> void:
	var board := BoardState.from_text("""
		X.
		.O
	""")
	board.insert_row(1)
	t.check_eq(board.to_text(), "X.\n..\n.O")
	board.insert_row(0)
	t.check_eq(board.to_text(), "..\nX.\n..\n.O")
	board.insert_row(4)
	t.check_eq(board.to_text(), "..\nX.\n..\n.O\n..")


func test_exact_five_in_all_directions() -> void:
	var horizontal := BoardState.from_text("XXXXX")
	t.check(horizontal.has_exact_five(Stone.BLACK), "가로")
	var vertical := BoardState.from_text("O\nO\nO\nO\nO")
	t.check(vertical.has_exact_five(Stone.WHITE), "세로")
	t.check(not vertical.has_exact_five(Stone.BLACK), "다른 색")
	var diagonal := BoardState.from_text("""
		X....
		.X...
		..X..
		...X.
		....X
	""")
	t.check(diagonal.has_exact_five(Stone.BLACK), "대각선 \\")
	var anti := BoardState.from_text("""
		....X
		...X.
		..X..
		.X...
		X....
	""")
	t.check(anti.has_exact_five(Stone.BLACK), "대각선 /")


func test_six_or_more_is_not_five() -> void:
	t.check(not BoardState.from_text("XXXXXX").has_exact_five(Stone.BLACK), "6목")
	t.check(not BoardState.from_text("XXXXXXX").has_exact_five(Stone.BLACK), "7목")
	t.check(not BoardState.from_text("XXXX.").has_exact_five(Stone.BLACK), "4목")
	t.check(BoardState.from_text("XXXXX.X").has_exact_five(Stone.BLACK), "5목 + 떨어진 돌")
	t.check(BoardState.from_text("OXXXXXO").has_exact_five(Stone.BLACK), "양쪽이 막힌 5목도 5목")


func test_line_splits_six_into_five() -> void:
	var board := BoardState.from_text("XXXXXX")
	board.insert_column(5)
	t.check_eq(board.to_text(), "XXXXX.X")
	var lines := board.find_exact_lines(Stone.BLACK)
	t.check_eq(lines.size(), 1)
	t.check_eq(lines[0][0], Vector2i(0, 0))
	t.check_eq(lines[0][4], Vector2i(4, 0))


func test_line_breaks_five() -> void:
	var board := BoardState.from_text("XXXXX")
	board.insert_column(2)
	t.check(not board.has_exact_five(Stone.BLACK))


func test_dict_round_trip() -> void:
	var board := BoardState.from_text("X.O\n.XO")
	var copy := BoardState.from_dict(JSON.parse_string(JSON.stringify(board.to_dict())))
	t.check_eq(copy.to_text(), board.to_text())
