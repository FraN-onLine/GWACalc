extends SceneTree
## Headless smoke test. Run with:
##   godot --headless --path . --script res://tests/smoke_test.gd
##
## Plays complete games: rounds, strikes, alternating turns, one-by-one reveals,
## totals carrying over between boards, question selection, editing and the tie-breaker.

var _failures: int = 0
var _checks: int = 0

## Set once the main scene is up, so shared helpers can reach the live game screen.
var _game: Control = null


func _init() -> void:
	call_deferred("_run")


func _check(label: String, actual: Variant, expected: Variant) -> void:
	_checks += 1
	if actual == expected:
		print("  PASS  %s = %s" % [label, actual])
	else:
		_failures += 1
		print("  FAIL  %s = %s (expected %s)" % [label, actual, expected])


func _ensure_gamedata() -> void:
	if root.get_node_or_null("GameData") != null:
		return
	var node := Node.new()
	node.set_script(load("res://scripts/game_data.gd"))
	node.name = "GameData"
	root.add_child(node)


func _score(game: Control, team: int) -> int:
	var label: Label = game.get_node("%TeamAScore" if team == 0 else "%TeamBScore")
	return int(label.text)


## The board now fills column by column (1 5 / 2 6 / 3 7 / 4 8), so grid children
## are not in answer order - always resolve a card by the index it was set up with.
func _card_at(grid: GridContainer, index: int) -> Node:
	for child in grid.get_children():
		if int(child.index) == index:
			return child
	return null


func _press_card(grid: GridContainer, index: int) -> void:
	_card_at(grid, index).get_node("%CardButton").pressed.emit()


## The printed numbers in display order: left to right, top to bottom.
func _display_order(grid: GridContainer) -> Array:
	var numbers := []
	for child in grid.get_children():
		numbers.append(int(child.get_node("%HiddenNumber").text))
	return numbers


func _hidden_cards(grid: GridContainer) -> int:
	var count := 0
	for child in grid.get_children():
		if not child.revealed:
			count += 1
	return count


## Clears the whole board, then drains any end-of-round reveals one card at a time,
## waits out the deliberate beat before the scoreboard lands, and proves the final
## reveal was left uncovered while it held.
func _finish_board(grid: GridContainer, reveal: Button) -> void:
	for i in grid.get_child_count():
		_press_card(grid, i)
		await process_frame
	while reveal.visible:
		reveal.pressed.emit()
		await process_frame

	if _game == null or float(_game.break_pause) <= 0.0:
		return
	var panel: Control = _game.get_node("%RoundBreak")
	_check("the score panel holds off - last reveal uncovered", panel.visible, false)
	await create_timer(float(_game.break_pause) + 0.4).timeout
	_check("score panel up after the pause", panel.visible, true)


func _run() -> void:
	await process_frame
	_ensure_gamedata()
	await process_frame

	# The test presses the real setup buttons, which save to disk. Keep a
	# byte-for-byte copy of both data files and put them back at the end, so the
	# suite can be run any number of times without touching the repo.
	var questions_backup := FileAccess.get_file_as_string("res://data/questions.json")
	var settings_backup := FileAccess.get_file_as_string("res://data/settings.json")

	var gamedata := root.get_node("GameData")

	print("\n--- CONTENT: the three supplied questions ---")
	_check("rounds loaded", gamedata.round_count(), 3)
	_check("tie-breaker available", gamedata.tie_breaker_available(), true)
	_check("Q1 answers", (gamedata.get_round(0)["answers"] as Array).size(), 8)
	_check("Q2 answers", (gamedata.get_round(1)["answers"] as Array).size(), 8)
	_check("Q3 answers", (gamedata.get_round(2)["answers"] as Array).size(), 8)
	_check("Q1 top answer", str((gamedata.get_round(0)["answers"] as Array)[0]["text"]), "Syntax")
	_check("Q1 top points", int((gamedata.get_round(0)["answers"] as Array)[0]["points"]), 30)
	_check("Q2 top answer", str((gamedata.get_round(1)["answers"] as Array)[0]["text"]), "Pera")
	_check("Q3 top points", int((gamedata.get_round(2)["answers"] as Array)[0]["points"]), 32)

	var totals: Array[int] = [0, 0, 0]
	for i in 3:
		for a: Dictionary in (gamedata.get_round(i)["answers"] as Array):
			totals[i] += int(a["points"])
	_check("Q1 totals 100", totals[0], 100)
	_check("Q2 totals 100", totals[1], 100)
	_check("Q3 totals 99 (as supplied)", totals[2], 99)

	print("\n--- PLAYLIST SELECTION ---")
	var playlist: Array[Dictionary] = gamedata.build_playlist([0, 1])
	_check("picked 2 of 3 boards", playlist.size(), 2)
	_check("kept the chosen order", str(playlist[1]["question"]).begins_with("Mga rasons kung bakit nag CS/IT"), true)
	_check("empty selection allowed", gamedata.build_playlist([]).size(), 0)

	print("\n--- MAIN MENU LEADS TO SETUP, SETUP STARTS THE GAME ---")
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var menu: Control = main.get_node("%MainMenu")
	var setup: Control = main.get_node("%SetupScreen")
	var game: Control = main.get_node("%GameScreen")
	var result: Control = main.get_node("%ResultScreen")
	var grid: GridContainer = game.get_node("%AnswerGrid")
	var reveal: Button = game.get_node("%RevealButton")
	_game = game
	var break_panel: Control = game.get_node("%RoundBreak")
	var break_title: Label = game.get_node("%BreakTitle")
	var break_team_a: Label = game.get_node("%BreakTeamAName")
	var break_score_a: Label = game.get_node("%BreakTeamAScore")
	var break_next: Button = game.get_node("%BreakNextButton")
	var miss: Button = game.get_node("%MissButton")

	_check("main menu shown at boot", menu.visible, true)
	_check("game hidden at boot", game.visible, false)
	_check("setup hidden at boot", setup.visible, false)
	_check("result hidden at boot", result.visible, false)
	_check("menu shows the matchup", menu.get_node("%MatchupLabel").text.contains("DCS"), true)

	menu.get_node("%HelpButton").pressed.emit()
	await process_frame
	_check("HOW TO PLAY opens the help overlay", menu.get_node("%HelpOverlay").visible, true)
	menu.get_node("%HelpCloseButton").pressed.emit()
	await process_frame
	_check("GOT IT closes the help overlay", menu.get_node("%HelpOverlay").visible, false)

	menu.get_node("%PlayButton").pressed.emit()
	await process_frame
	_check("PLAY opens the setup screen", setup.visible, true)
	_check("menu hidden while setting up", menu.visible, false)

	setup.get_node("%StartButton").pressed.emit()
	await process_frame
	await process_frame
	_check("START GAME launches the board", game.visible, true)
	_check("setup hidden once the game starts", setup.visible, false)
	_check("8 cards on board 1", grid.get_child_count(), 8)
	_check("board reads down the columns", _display_order(grid), [1, 5, 2, 6, 3, 7, 4, 8])
	_check("printed number follows the answer, not the slot",
		_card_at(grid, 4).get_node("%HiddenNumber").text, "5")
	_check("hidden card shows one big centred number",
		[_card_at(grid, 0).get_node("%HiddenNumber").visible,
		_card_at(grid, 0).get_node("%Row").visible], [true, false])
	_check("round label", game.get_node("%RoundLabel").text, "ROUND 1")
	_check("question shown", game.get_node("%QuestionLabel").text.begins_with("Mga rason kung bakit hindi"), true)


	print("\n--- TURNS ALTERNATE AND POINTS ACCUMULATE ---")
	_press_card(grid, 0)                                  # DCS takes "Syntax" = 30
	await process_frame
	_check("DCS banked 30", _score(game, 0), 30)
	_check("turn passed to DIT", game.get_node("%TurnLabel").text, "ANSWERING: DIT")
	var revealed_card: Node = _card_at(grid, 0)
	_check("revealed card swaps the number for the answer",
		[revealed_card.get_node("%HiddenNumber").visible, revealed_card.get_node("%Row").visible],
		[false, true])
	_check("answer text shown on the card", revealed_card.get_node("%Text").text, "Syntax")
	_check("gold points box shows the value", revealed_card.get_node("%Points").text, "30")

	_press_card(grid, 1)                                  # DIT takes "Semicolon" = 24
	await process_frame
	_check("DIT banked 24", _score(game, 1), 24)
	_check("turn back to DCS", game.get_node("%TurnLabel").text, "ANSWERING: DCS")

	print("\n--- THREE WRONG ANSWERS PASS THE TURN ---")
	_check("no X on screen before a miss", game.get_node("%StrikeX").visible, false)
	miss.pressed.emit()
	await process_frame
	_check("a big X flashes on screen", game.get_node("%StrikeX").visible, true)
	var x_size: int = game.get_node("%StrikeXLabel").get_theme_font_size("font_size")
	print("  strike X font size: %d px" % x_size)
	_check("the X is huge", x_size >= 250, true)
	await create_timer(1.7).timeout
	_check("the X fades away again", game.get_node("%StrikeX").visible, false)

	for i in 2:
		miss.pressed.emit()
		await process_frame
	_check("turn passes on the 3rd strike", game.get_node("%TurnLabel").text, "ANSWERING: DIT")
	_check("strikes reset for the new team", game.get_node("%StrikeLabel").text.contains("[X]"), false)
	_check("wrong answers score nothing", [_score(game, 0), _score(game, 1)], [30, 24])
	_check("guesses counted", game.get_node("%GuessesLabel").text, "GUESSES: 5 / 10")

	print("\n--- ROUND 1 CLOSES, TOTALS CARRY INTO ROUND 2 ---")
	await _finish_board(grid, reveal)
	var dcs_after_r1 := _score(game, 0)
	var dit_after_r1 := _score(game, 1)
	_check("round-over score panel appears", break_panel.visible, true)
	_check("panel title marks the round done", break_title.text, "ROUND 1 COMPLETE")
	_check("panel shows team 1", break_team_a.text, "DCS")
	_check("panel shows team 1's total", break_score_a.text, str(dcs_after_r1))
	_check("panel offers the next question", break_next.text.begins_with("NEXT QUESTION"), true)

	break_next.pressed.emit()
	await process_frame
	await process_frame
	_check("score panel closes for the next board", break_panel.visible, false)
	_check("round 2 label", game.get_node("%RoundLabel").text, "ROUND 2")
	_check("round 2 board built", grid.get_child_count(), 8)
	_check("guesses reset", game.get_node("%GuessesLabel").text, "GUESSES: 0 / 10")
	_check("DCS total carried over", _score(game, 0), dcs_after_r1)
	_check("DIT total carried over", _score(game, 1), dit_after_r1)
	_check("round 2 question shown", game.get_node("%QuestionLabel").text.begins_with("Mga rasons kung bakit nag CS/IT"), true)

	var pera_before := _score(game, 1)
	_check("DIT total before the top answer", pera_before, dit_after_r1)
	_press_card(grid, 0)                                  # "Pera" = 25 goes to whoever is answering
	await process_frame
	_check("top answer of Q2 scored", _score(game, 0) + _score(game, 1), dcs_after_r1 + dit_after_r1 + 25)
	_check("answering team got it", maxi(_score(game, 0), _score(game, 1)), maxi(dcs_after_r1, dit_after_r1) + 25)
	_check("other team unchanged", mini(_score(game, 0), _score(game, 1)), mini(dcs_after_r1, dit_after_r1))

	print("\n--- HOST CAN FORCE WHO ANSWERS ---")
	var btn_a: Button = game.get_node("%TeamAButton")
	var btn_b: Button = game.get_node("%TeamBButton")
	btn_a.pressed.emit()
	await process_frame
	_check("forced to DCS", game.get_node("%TurnLabel").text, "ANSWERING: DCS")
	btn_b.pressed.emit()
	await process_frame
	_check("forced to DIT", game.get_node("%TurnLabel").text, "ANSWERING: DIT")

	await _finish_board(grid, reveal)
	_check("score panel returns between rounds", break_panel.visible, true)
	break_next.pressed.emit()
	await process_frame
	await process_frame
	_check("round 3 reached", game.get_node("%RoundLabel").text, "ROUND 3")
	_check("round 3 board built", grid.get_child_count(), 8)
	_check("round 3 question shown", game.get_node("%QuestionLabel").text.contains("iniiyakan"), true)

	await _finish_board(grid, reveal)
	_check("final score panel appears", break_panel.visible, true)
	_check("final panel title", break_title.text, "FINAL ROUND COMPLETE")
	_check("final panel offers the results", break_next.text.begins_with("SEE RESULTS"), true)
	break_next.pressed.emit()
	await process_frame
	await process_frame

	print("\n--- FINAL RESULT AFTER 3 BOARDS ---")
	_check("result screen shown", result.visible, true)
	_check("game hidden", game.visible, false)

	var final_a := _score(game, 0)
	var final_b := _score(game, 1)
	var title: String = result.get_node("%Title").text
	var leader := "DCS" if final_a > final_b else "DIT"
	_check("totals are non-zero", final_a + final_b > 0, true)
	_check("winner is the higher score", title.begins_with(leader), true)
	_check("breakdown lists every round", result.get_node("%Breakdown").text.contains("ROUND 1")
		and result.get_node("%Breakdown").text.contains("ROUND 2")
		and result.get_node("%Breakdown").text.contains("ROUND 3"), true)
	_check("exactly 3 rounds logged", game._round_log.size(), 3)



	print("\n--- SETUP PANEL TOGGLES THE QUESTION LIST ---")
	main.open_setup()
	await process_frame
	_check("setup opens over the board", setup.visible, true)
	_check("game hidden while setting up", game.visible, false)

	var toggles: Array[CheckButton] = setup.toggles()
	_check("one checkbox per question", toggles.size(), 3)
	_check("all ticked by default", toggles[0].button_pressed and toggles[2].button_pressed, true)
	_check("summary counts the ticks", setup.get_node("%SummaryLabel").text.begins_with("3 of 3"), true)

	print("\n--- TEAMS AND RULES ARE EDITABLE ---")
	var team_a: LineEdit = setup.get_node("%TeamAEdit")
	var starter: OptionButton = setup.get_node("%StarterOption")
	_check("starter options built", starter.item_count, 3)
	team_a.text = "CCIS"
	team_a.text_changed.emit("CCIS")
	await process_frame
	_check("summary follows a rename", setup.get_node("%SummaryLabel").text.contains("CCIS vs DIT"), true)
	_check("starter choice follows the rename", starter.get_item_text(0), "CCIS first")
	team_a.text = "DCS"
	team_a.text_changed.emit("DCS")

	print("\n--- RUNNING ONLY A SUBSET OF QUESTIONS ---")
	toggles[0].button_pressed = false
	toggles[1].button_pressed = true
	toggles[2].button_pressed = false
	setup._update_summary()
	await process_frame
	_check("summary follows the ticks", setup.get_node("%SummaryLabel").text.begins_with("1 of 3"), true)

	setup._on_start_game()
	await process_frame
	await process_frame
	_check("setup closed after starting", setup.visible, false)
	_check("only the chosen board is played", game.get_node("%RoundLabel").text, "ROUND 2")
	_check("scores reset on restart", [_score(game, 0), _score(game, 1)], [0, 0])
	_check("board matches question 2", grid.get_child_count(), 8)

	await _finish_board(grid, reveal)
	_check("single board pauses at the score panel", break_panel.visible, true)
	_check("single board panel title", break_title.text, "FINAL ROUND COMPLETE")
	break_next.pressed.emit()
	await process_frame
	await process_frame
	_check("single-board game reaches the results", result.visible, true)

	print("\n--- ADD / EDIT / REORDER QUESTIONS ---")
	var before: int = gamedata.round_count()
	var added: int = gamedata.add_round()
	_check("new question appended", gamedata.round_count(), before + 1)
	_check("new question starts with blank rows", (gamedata.get_round(added)["answers"] as Array).size(), 5)

	gamedata.update_round(added, {
		"name": "Round 4",
		"question": "Bagong tanong?",
		"answers": [
			{"text": "B", "points": 5},
			{"text": "A", "points": 20},
			{"text": "C", "points": 10},
		],
	})
	var edited: Dictionary = gamedata.get_round(added)
	_check("question text stored", str(edited["question"]), "Bagong tanong?")
	_check("answers re-sorted by points", str((edited["answers"] as Array)[0]["text"]), "A")
	_check("answer count stored", (edited["answers"] as Array).size(), 3)

	gamedata.update_round(added, {"question": "Walang points", "answers": [{"text": "X", "points": 0}]})
	_check("answers without points are dropped", (gamedata.get_round(added)["answers"] as Array).size(), 0)

	gamedata.move_round(added, -1)
	_check("question moved up", str(gamedata.get_round(before - 1)["question"]), "Walang points")
	gamedata.remove_round(before - 1)
	_check("question removed", gamedata.round_count(), before)

	print("\n--- TIE-BREAKER (guideline 11) ---")
	var tie_config: Dictionary = gamedata.make_game_config({
		"teams": ["DCS", "DIT"],
		"playlist": gamedata.build_playlist([0]),
		"guesses_per_round": 10,
		"tie_breaker_enabled": true,
	})
	setup.start_requested.emit(tie_config)
	await process_frame
	await process_frame
	_check("single board loaded", game.get_node("%RoundLabel").text, "ROUND 1")

	# Level the totals, then clear the last card to close the round and force the tie-breaker.
	for i in range(0, grid.get_child_count() - 1):
		_press_card(grid, i)
		await process_frame

	var last_card: Node = _card_at(grid, grid.get_child_count() - 1)
	var answering: int = game._turn
	game._scores = PackedInt32Array([40, 40])
	game._scores[answering] = 40 - int(last_card.points)   # last card lands exactly level

	_press_card(grid, grid.get_child_count() - 1)
	await process_frame
	_check("the last reveal stays uncovered during the pause", break_panel.visible, false)
	await create_timer(game.break_pause + 0.4).timeout

	_check("totals are level", [_score(game, 0), _score(game, 1)], [40, 40])
	_check("level totals pause at the score panel", break_panel.visible, true)
	_check("panel offers the tie-break question", break_next.text.begins_with("NEXT QUESTION"), true)
	break_next.pressed.emit()
	await process_frame
	await process_frame
	_check("tie-breaker board loaded", game.get_node("%RoundLabel").text, "TIE-BREAKER")
	_check("tie-breaker flag set", game._in_tiebreaker, true)
	_check("tie-breaker has 4 answers", grid.get_child_count(), 4)

	await _finish_board(grid, reveal)
	_check("tie-breaker ends at the score panel", break_panel.visible, true)
	_check("tie-break panel title", break_title.text, "TIE-BREAKER COMPLETE")
	break_next.pressed.emit()
	await process_frame
	await process_frame
	_check("decided on the tie-breaker", result.get_node("%Title").text.ends_with("TIE-BREAKER!"), true)
	_check("every tie-breaker answer was split", game._tie_points[0] + game._tie_points[1], 100)
	var tie_leader := "DCS" if game._tie_points[0] > game._tie_points[1] else "DIT"
	_check("tie-break winner took the higher share", result.get_node("%Title").text.begins_with(tie_leader), true)
	_check("tie points kept out of the totals", [_score(game, 0), _score(game, 1)], [40, 40])

	print("\n--- MAIN MENU IS ALWAYS ONE PRESS AWAY ---")
	main.show_menu()
	await process_frame
	_check("menu reachable after a game", menu.visible, true)
	_check("every other screen hidden", [game.visible, setup.visible, result.visible], [false, false, false])
	_check("menu still shows the teams", menu.get_node("%MatchupLabel").text.contains("DCS"), true)

	print("\n--- CANCELLING SETUP RETURNS WHERE YOU CAME FROM ---")
	main.open_setup()
	await process_frame
	_check("setup opened from the menu", setup.visible, true)
	setup.get_node("%BackButton").pressed.emit()
	await process_frame
	_check("BACK from the menu goes to the menu", menu.visible, true)
	_check("no stale board left behind", [game.visible, setup.visible, result.visible], [false, false, false])

	print("\n--- DATA FILES PUT BACK ---")
	_restore_file("res://data/questions.json", questions_backup)
	_restore_file("res://data/settings.json", settings_backup)
	_check("questions.json restored byte for byte",
		FileAccess.get_file_as_string("res://data/questions.json") == questions_backup, true)
	_check("settings.json restored byte for byte",
		FileAccess.get_file_as_string("res://data/settings.json") == settings_backup, true)

	print("\n==============================")
	print("checks: %d   failures: %d" % [_checks, _failures])
	print("==============================\n")
	quit(1 if _failures > 0 else 0)


## Writes a file back byte for byte.
func _restore_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

