extends SceneTree
## Round-trip test for the in-game editor's save button and the team-name save.
## Adds a question, writes res://data/questions.json, reloads from disk and checks it
## survived - then puts BOTH json files back byte for byte, so this test is safe to run
## as often as you like and leaves the repo exactly as it found it.

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("  PASS  %s = %s" % [label, actual])
	else:
		_failures += 1
		print("  FAIL  %s = %s (expected %s)" % [label, actual, expected])


func _run() -> void:
	await process_frame
	var node := Node.new()
	node.set_script(load("res://scripts/game_data.gd"))
	node.name = "GameData"
	root.add_child(node)
	await process_frame

	var gd := root.get_node("GameData")
	_check("loaded rounds", gd.round_count(), 3)

	# Snapshot both files so the test can put them back exactly as they were.
	var questions_backup := FileAccess.get_file_as_string("res://data/questions.json")
	var settings_backup := FileAccess.get_file_as_string("res://data/settings.json")
	var original_rounds: int = gd.round_count()
	var original_a: String = gd.teams[0]
	var original_b: String = gd.teams[1]

	var index: int = gd.add_round()
	gd.update_round(index, {
		"name": "Round 4",
		"question": "Sino ang unang naisip?",
		"answers": [
			{"text": "Jowa", "points": 9},
			{"text": "Kaibigan", "points": 31},
			{"text": "Kapatid", "points": 15},
		],
	})

	print("  saving to res://data/questions.json ...")
	var problem: String = gd.save()
	_check("save reported no error", problem, "")

	# Wipe the in-memory copy and read the file back from disk.
	gd.rounds.clear()
	gd.reload()

	_check("rounds after reload", gd.round_count(), 4)
	var saved: Dictionary = gd.get_round(3)
	_check("question survived", str(saved["question"]), "Sino ang unang naisip?")
	_check("answers survived", (saved["answers"] as Array).size(), 3)
	_check("sorted by points", str((saved["answers"] as Array)[0]["text"]), "Kaibigan")
	_check("points survived", int((saved["answers"] as Array)[0]["points"]), 31)
	_check("tie-breaker preserved", gd.tie_breaker_available(), true)
	_check("earlier rounds untouched", str(gd.get_round(0)["question"]).begins_with("Mga rason kung bakit hindi"), true)

	print("  settings.json round-trip ...")
	var settings_problem: String = gd.save_settings("Alpha Squad", "Beta Squad", {"guesses_per_round": 7})
	_check("settings save reported no error", settings_problem, "")
	gd.reload()
	_check("team names survived", [gd.teams[0], gd.teams[1]], ["Alpha Squad", "Beta Squad"])
	_check("chosen rule survived", int(gd.rules["guesses_per_round"]), 7)

	print("  putting both files back ...")
	_restore_file("res://data/questions.json", questions_backup)
	_restore_file("res://data/settings.json", settings_backup)
	gd.reload()
	_check("questions.json restored", gd.round_count(), original_rounds)
	_check("settings.json restored", [gd.teams[0], gd.teams[1]], [original_a, original_b])
	_check("team names returned to normal", [gd.teams[0], gd.teams[1]], ["DCS", "DIT"])

	print("  failures: %d\n" % _failures)
	quit(1 if _failures > 0 else 0)


## Writes a file back byte for byte.
func _restore_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
