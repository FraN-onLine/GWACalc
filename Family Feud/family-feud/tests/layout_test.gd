extends SceneTree
## Layout guard: the setup screen has to fit a 1600x900 window with no scrolling,
## because the host is reading it off a projector mid-show.
##   godot --headless --path . --script res://tests/layout_test.gd

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


## --script runs do not build autoloads, so stand one up by hand (as smoke_test does).
func _ensure_gamedata() -> void:
	if root.get_node_or_null("GameData") != null:
		return
	var node := Node.new()
	node.set_script(load("res://scripts/game_data.gd"))
	node.name = "GameData"
	root.add_child(node)


func _check(label: String, ok: bool, detail: String = "") -> void:
	var suffix := "" if detail.is_empty() else "  (%s)" % detail
	if ok:
		print("  PASS  %s%s" % [label, suffix])
	else:
		_failures += 1
		print("  FAIL  %s%s" % [label, suffix])


func _run() -> void:
	await process_frame
	_ensure_gamedata()
	await process_frame

	# Headless opens a tiny window, and the project stretches to fit. Pin the canvas
	# to the design size so these measurements describe the real 1600x900 show.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 900)
	await process_frame
	await process_frame

	# The real START button saves to disk. Keep a copy of both data files and put
	# them back at the end so this suite never leaves the repo touched.
	var questions_backup := FileAccess.get_file_as_string("res://data/questions.json")
	var settings_backup := FileAccess.get_file_as_string("res://data/settings.json")

	var main: Control = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var view := root.get_visible_rect().size
	var setup: Control = main.get_node("%SetupScreen")
	var menu: Control = main.get_node("%MainMenu")

	print("\n--- MAIN MENU ---")
	var menu_box: Control = menu.get_node("Center/VBox")
	_check(
		"menu fits the window",
		menu_box.get_global_rect().end.y <= view.y,
		"bottom %.0f / %.0f" % [menu_box.get_global_rect().end.y, view.y]
	)

	menu.get_node("%HelpButton").pressed.emit()
	await process_frame
	var help_panel: Control = menu.get_node("HelpOverlay/Center/Panel")
	var help_body: Label = menu.get_node("HelpOverlay/Center/Panel/Margin/VBox/Body")
	print("  help panel %.0f tall; body %s with %d wrapped lines" % [
		help_panel.size.y, help_body.size, help_body.get_line_count()
	])
	_check(
		"help overlay fits the window",
		help_panel.size.y <= view.y,
		"%.0f / %.0f" % [help_panel.size.y, view.y]
	)
	menu.close_help()
	await process_frame

	main.open_setup()
	await process_frame
	await process_frame

	print("\n--- SETUP SCREEN FITS WITHOUT SCROLLING ---")
	var footer: Control = setup.get_node("Layout/VBox/Footer")
	var body: Control = setup.get_node("Layout/VBox/Body")
	print("  viewport %.0fx%.0f   setup %.0fx%.0f   body height %.0f" % [
		view.x, view.y, setup.size.x, setup.size.y, body.size.y
	])

	_check("setup fills the window", setup.size == view, "%.0fx%.0f" % [setup.size.x, setup.size.y])
	_check(
		"header and footer stay on screen",
		footer.get_global_rect().end.y <= view.y + 0.5,
		"footer bottom %.0f / %.0f" % [footer.get_global_rect().end.y, view.y]
	)

	var scroll: ScrollContainer = setup.get_node("Layout/VBox/Body/BankPanel/Margin/VBox/ListScroll")
	var list: Control = setup.get_node("%QuestionList")
	var row_pitch := (list.size.y + 5.0) / maxf(float(list.get_child_count()), 1.0)
	var visible_rows := int((scroll.size.y + 5.0) / row_pitch)
	print("  a bank row is about %.0f px; the visible list holds about %d" % [row_pitch, visible_rows])

	_check(
		"3 questions need no scrolling",
		list.size.y <= scroll.size.y + 0.5,
		"content %.0f / visible %.0f" % [list.size.y, scroll.size.y]
	)
	_check("room for at least 12 questions without scrolling", visible_rows >= 12, "%d rows" % visible_rows)
	_check("bank rows stay compact", row_pitch <= 40.0, "%.0f px each" % row_pitch)

	var settings: Control = setup.get_node("Layout/VBox/Body/SettingsPanel")
	_check(
		"teams and rules panel fits too",
		settings.size.y <= body.size.y + 0.5,
		"%.0f / %.0f" % [settings.size.y, body.size.y]
	)

	print("\n--- QUESTION EDITOR FITS WITHOUT SCROLLING ---")
	var editor: Control = setup.get_node("%QuestionEditor")
	editor.open(root.get_node("GameData").get_round(0), 0)
	await process_frame
	await process_frame
	var panel: Control = editor.get_node("Center/Panel")
	_check(
		"editor panel fits the window",
		panel.size.y <= view.y,
		"%.0f / %.0f" % [panel.size.y, view.y]
	)
	_check("live points total shown", editor.get_node("%TotalLabel").text.contains("100"), editor.get_node("%TotalLabel").text)
	editor.close()

	print("\n--- GAME BOARD FITS WITHOUT SCROLLING ---")
	setup.get_node("%StartButton").pressed.emit()
	await process_frame
	await process_frame
	var game: Control = main.get_node("%GameScreen")
	var board_scroll: ScrollContainer = game.get_node("Layout/VBox/Board")
	var grid: GridContainer = game.get_node("%AnswerGrid")
	var card: Control = grid.get_child(0)
	print("  board area %.0f px tall; grid %.0f px; card %.0f px; %d cards" % [
		board_scroll.size.y, grid.size.y, card.size.y, grid.get_child_count()
	])

	_check("game screen launched", game.visible)
	_check(
		"all 8 cards fit without scrolling",
		grid.size.y <= board_scroll.size.y + 0.5,
		"grid %.0f / board %.0f" % [grid.size.y, board_scroll.size.y]
	)
	_check("no scrollbar needed", board_scroll.scroll_vertical == 0,
		"scroll position %d" % board_scroll.scroll_vertical)
	_check("cards stay compact", card.size.y <= 90.0, "%.0f px tall" % card.size.y)
	var order := []
	var on_screen := true
	for child in grid.get_children():
		order.append(int(child.get_node("%HiddenNumber").text))
		if child.get_global_rect().end.y > view.y + 0.5:
			on_screen = false
	print("  display order: %s" % [order])
	_check("board reads 1 5 / 2 6 / 3 7 / 4 8", order == [1, 5, 2, 6, 3, 7, 4, 8], str(order))
	_check("every card sits inside the window", on_screen)

	print("\n--- BETWEEN-ROUNDS SCORE PANEL FITS ---")
	game.break_pause = 0.0   # geometry only: skip the deliberate reveal beat
	game._close_round()
	await process_frame
	await process_frame
	var brk: Control = game.get_node("%RoundBreak")
	var brk_panel: Control = brk.get_node("Center/Panel")
	print("  score panel %.0f x %.0f, window %.0f x %.0f" % [
		brk_panel.size.x, brk_panel.size.y, view.x, view.y
	])
	_check("score panel appears when a board closes", brk.visible)
	_check("score panel fits the window",
		brk_panel.size.x <= view.x and brk_panel.size.y <= view.y,
		"panel %.0fx%.0f / view %.0fx%.0f" % [brk_panel.size.x, brk_panel.size.y, view.x, view.y])

	print("\n--- RESULT SCREEN FITS ---")
	var result: Control = main.get_node("%ResultScreen")
	var summary := {
		"teams": ["DCS", "DIT"],
		"scores": PackedInt32Array([120, 95]),
		"winner": 0,
		"was_tiebreaker": false,
		"rounds": [{"name": "Round 1", "scores": PackedInt32Array([50, 40])}],
	}
	result.visible = true
	result.show_result(summary)
	await process_frame
	print("  result panel height %.0f" % result.get_node("Center/Panel").size.y)

	print("\n--- DATA FILES PUT BACK ---")
	_restore_file("res://data/questions.json", questions_backup)
	_restore_file("res://data/settings.json", settings_backup)
	_check("questions.json restored",
		FileAccess.get_file_as_string("res://data/questions.json") == questions_backup,
		"byte for byte"
	)
	_check("settings.json restored",
		FileAccess.get_file_as_string("res://data/settings.json") == settings_backup,
		"byte for byte"
	)

	print("\nlayout failures: %d\n" % _failures)
	quit(1 if _failures > 0 else 0)


## Writes a file back byte for byte.
func _restore_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
