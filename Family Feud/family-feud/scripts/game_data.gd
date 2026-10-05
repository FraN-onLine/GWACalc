extends Node
## Autoload: "GameData".
##
## Loads and validates every piece of content the game needs:
##   res://data/settings.json  -> team names + default rules
##   res://data/questions.json -> rounds (question + answer board) + tie-breaker
##
## Changing teams, questions, answers or points only ever means editing those two
## JSON files. No scene and no script has to be touched.

const SETTINGS_PATH := "res://data/settings.json"
const QUESTIONS_PATH := "res://data/questions.json"

## How a round picks the team that answers first.
const STARTER_TEAM_A := 0
const STARTER_TEAM_B := 1
const STARTER_ALTERNATE := 2

const DEFAULT_TEAMS: Array[String] = ["DCS", "DIT"]

## Fallback for any key missing from settings.json.
const DEFAULT_RULES := {
	"guesses_per_round": 10,
	"strikes_per_turn": 3,
	"seconds_per_guess": 0,
	"tie_breaker_enabled": true,
	"first_round_starter": STARTER_ALTERNATE,
	"answer_columns": 0,
}

var teams: Array[String] = ["DCS", "DIT"]
var rules: Dictionary = {}
var rounds: Array[Dictionary] = []
var tie_breaker: Dictionary = {}

## The parsed questions.json, kept so save() can preserve unknown keys such as _readme.
var _raw_questions: Dictionary = {}

## The parsed settings.json, kept so save_settings() can preserve _readme / _rules.
var _raw_settings: Dictionary = {}

## Non fatal problems found while loading (shown to the host in the Setup screen).
var notices: Array[String] = []


func _ready() -> void:
	reload()


## Re-reads both JSON files. Call this after editing content at runtime.
func reload() -> void:
	notices.clear()
	rules = DEFAULT_RULES.duplicate()
	rounds.clear()
	tie_breaker = {}

	var raw_settings: Variant = _read_json(SETTINGS_PATH, {})
	if raw_settings is Dictionary:
		_raw_settings = raw_settings
		for key: Variant in DEFAULT_RULES:
			if raw_settings.has(key):
				rules[key] = raw_settings[key]
		teams = _sanitize_teams(raw_settings.get("teams", null))
	else:
		_raw_settings = {}
		teams = DEFAULT_TEAMS.duplicate()

	var raw_questions: Variant = _read_json(QUESTIONS_PATH, {})
	if raw_questions is Dictionary:
		_raw_questions = raw_questions
		rounds = _parse_rounds(raw_questions.get("rounds", []))
		tie_breaker = _parse_tie_breaker(raw_questions.get("tie_breaker", null))
	else:
		_raw_questions = {}
		notices.append("questions.json is missing or invalid - no rounds loaded.")

	if rounds.is_empty():
		notices.append("No usable rounds found. Check res://data/questions.json.")


# ============================================================
# QUERIES
# ============================================================

func round_count() -> int:
	return rounds.size()


func has_round(index: int) -> bool:
	return index >= 0 and index < rounds.size()


## Safe accessor - returns an empty dictionary instead of crashing on a bad index.
func get_round(index: int) -> Dictionary:
	if not has_round(index):
		return {}
	return rounds[index]


func get_round_title(index: int) -> String:
	var round := get_round(index)
	if round.is_empty():
		return "Round %d" % (index + 1)
	return str(round.get("name", "Round %d" % (index + 1)))


## True when a tie-breaker board exists AND is enabled in the rules.
func tie_breaker_available() -> bool:
	return not tie_breaker.is_empty() and bool(rules.get("tie_breaker_enabled", true))


# ============================================================
# GAME CONFIG  (merged with whatever the host set in the Setup screen)
# ============================================================

## The boards the host ticked, in the order they will be played.
func build_playlist(indices: Array) -> Array[Dictionary]:
	var playlist: Array[Dictionary] = []
	for value: Variant in indices:
		var index := int(value)
		if has_round(index):
			playlist.append(get_round(index))
	return playlist


func make_game_config(overrides: Dictionary = {}) -> Dictionary:
	var playlist: Array[Dictionary] = overrides.get("playlist", build_playlist(all_round_indices()))
	var config := {
		"teams": teams.duplicate(),
		"rounds": playlist,
		"round_count": playlist.size(),
		"guesses_per_round": int(rules.get("guesses_per_round", 10)),
		"strikes_per_turn": int(rules.get("strikes_per_turn", 3)),
		"seconds_per_guess": int(rules.get("seconds_per_guess", 0)),
		"tie_breaker_enabled": tie_breaker_available(),
		"first_round_starter": int(rules.get("first_round_starter", STARTER_ALTERNATE)),
		"answer_columns": int(rules.get("answer_columns", 0)),
	}
	for key: Variant in overrides:
		if key == "playlist":
			continue
		config[key] = overrides[key]
	return config


## Every round index - the default playlist is "all of them, in order".
func all_round_indices() -> Array:
	var indices: Array = []
	for i in rounds.size():
		indices.append(i)
	return indices


## Team index that answers first in the given round, honouring first_round_starter.
func starter_for_round(round_index: int, first_starter: int) -> int:
	match first_starter:
		STARTER_TEAM_B:
			return 1
		STARTER_ALTERNATE:
			return round_index % 2
		_:
			return 0


# ============================================================
# PARSING / VALIDATION
# ============================================================

func _read_json(path: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		notices.append("File not found: %s" % path)
		return fallback

	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		notices.append("File is empty: %s" % path)
		return fallback

	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		notices.append(
			"%s has invalid JSON (line %d): %s"
			% [path.get_file(), json.get_error_line(), json.get_error_message()]
		)
		return fallback
	return json.data


func _sanitize_teams(raw: Variant) -> Array[String]:
	if not (raw is Array):
		notices.append("settings.json: 'teams' must be an array - using DCS vs DIT.")
		return DEFAULT_TEAMS.duplicate()

	var names: Array[String] = []
	for entry: Variant in raw:
		names.append(str(entry).strip_edges())

	while names.size() > 2 and names[names.size() - 1].is_empty():
		names.remove_at(names.size() - 1)

	if names.size() != 2:
		notices.append("Exactly 2 team names are required (found %d) - using DCS vs DIT." % names.size())
		return DEFAULT_TEAMS.duplicate()

	if names[0].is_empty() or names[1].is_empty():
		notices.append("Team names cannot be empty - using DCS vs DIT.")
		return DEFAULT_TEAMS.duplicate()

	if names[0].to_upper() == names[1].to_upper():
		notices.append("Both teams have the same name - using DCS vs DIT.")
		return DEFAULT_TEAMS.duplicate()

	return names


func _parse_rounds(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (raw is Array):
		notices.append("questions.json: 'rounds' must be an array.")
		return result

	for i in int(raw.size()):
		var round_index := i + 1
		var entry: Variant = raw[i]
		if not (entry is Dictionary):
			notices.append("Round %d is not an object - skipped." % round_index)
			continue

		var question := str(entry.get("question", "")).strip_edges()
		if question.is_empty():
			notices.append("Round %d has no question - skipped." % round_index)
			continue

		var answers := _parse_answers(entry.get("answers", []), round_index)
		if answers.is_empty():
			notices.append("Round %d has no usable answers - skipped." % round_index)
			continue

		result.append({
			"name": str(entry.get("name", "Round %d" % round_index)),
			"question": question,
			"answers": answers,
		})

	return result


func _parse_tie_breaker(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}

	var question := str(raw.get("question", "")).strip_edges()
	var answers := _parse_answers(raw.get("answers", []), 0)
	if question.is_empty() or answers.is_empty():
		notices.append("Tie-breaker needs a question and at least one answer - disabled.")
		return {}

	return {
		"name": str(raw.get("name", "Tie-Breaker")),
		"question": question,
		"answers": answers,
	}


## Normalises one answer board: drops junk, sorts by points (highest first), checks the 100 total.
func _parse_answers(raw: Variant, round_index: int) -> Array[Dictionary]:
	var label := "Tie-breaker" if round_index == 0 else "Round %d" % round_index
	var result: Array[Dictionary] = []

	if not (raw is Array):
		notices.append("%s: 'answers' must be an array - skipped." % label)
		return result

	for i in int(raw.size()):
		var entry: Variant = raw[i]
		if not (entry is Dictionary):
			notices.append("%s: answer #%d is not an object - skipped." % [label, i + 1])
			continue

		var answer_text := str(entry.get("text", "")).strip_edges()
		var points := int(entry.get("points", 0))

		if answer_text.is_empty():
			notices.append("%s: answer #%d has no text - skipped." % [label, i + 1])
			continue
		if points <= 0:
			notices.append("%s: '%s' has no points - skipped." % [label, answer_text])
			continue

		result.append({"text": answer_text, "points": points})

	if result.is_empty():
		return result

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("points", 0)) > int(b.get("points", 0))
	)

	var total := 0
	var seen: Dictionary = {}
	for answer: Dictionary in result:
		total += int(answer["points"])
		var key := str(answer["text"]).to_lower()
		if seen.has(key):
			notices.append("%s: duplicate answer '%s'." % [label, answer["text"]])
		seen[key] = true

	if total != 100:
		notices.append("%s: answers total %d points (100 is the usual survey total)." % [label, total])

	return result


# ============================================================
# EDITING  (driven by the in-game SETUP panel)
# ============================================================

## Adds an empty board at the end and returns its index.
func add_round() -> int:
	rounds.append({
		"name": "Round %d" % (rounds.size() + 1),
		"question": "",
		"answers": _blank_answers(5),
	})
	return rounds.size() - 1


## Replaces a board. Pass index == -1 to insert a new one at the end.
func update_round(index: int, board: Dictionary) -> int:
	var normalised := _normalise_board(board, index + 1)
	if index < 0 or index >= rounds.size():
		rounds.append(normalised)
		return rounds.size() - 1
	rounds[index] = normalised
	return index


func remove_round(index: int) -> void:
	if index >= 0 and index < rounds.size():
		rounds.remove_at(index)


func move_round(index: int, offset: int) -> int:
	var target := index + offset
	if index < 0 or index >= rounds.size() or target < 0 or target >= rounds.size():
		return index
	var board: Dictionary = rounds[index]
	rounds.remove_at(index)
	rounds.insert(target, board)
	return target


func set_tie_breaker(board: Dictionary) -> void:
	if board.is_empty():
		tie_breaker = {}
		return
	tie_breaker = _normalise_board(board, 0)


func duplicate_round(index: int) -> int:
	if index < 0 or index >= rounds.size():
		return index
	var copy: Dictionary = rounds[index].duplicate(true)
	copy["name"] = "%s (copy)" % str(copy.get("name", "Round"))
	rounds.insert(index + 1, copy)
	return index + 1


## Writes the team names (plus the rules the host picked in Setup) back to
## res://data/settings.json so the next launch opens the same way.
## Returns an empty string on success, otherwise the reason it failed.
func save_settings(team_a: String, team_b: String, overrides: Dictionary = {}) -> String:
	var name_a := team_a.strip_edges()
	var name_b := team_b.strip_edges()
	if name_a.is_empty() or name_b.is_empty() or name_a.to_upper() == name_b.to_upper():
		return "Team names must be two different, non-empty names."

	teams[0] = name_a
	teams[1] = name_b
	for key: Variant in DEFAULT_RULES:
		if overrides.has(key):
			rules[key] = overrides[key]

	var payload: Dictionary = _raw_settings.duplicate(true)
	payload["teams"] = teams
	for key: Variant in DEFAULT_RULES:
		payload[key] = rules[key]

	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return "Cannot write %s (error %d). An exported build cannot save to res://." % [
			SETTINGS_PATH, FileAccess.get_open_error()
		]
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return ""


## Writes rounds + tie-breaker back to res://data/questions.json.
## Returns an empty string on success, otherwise the reason it failed.
func save() -> String:
	var payload: Dictionary = _raw_questions.duplicate(true)
	payload["rounds"] = rounds
	payload["tie_breaker"] = tie_breaker

	var file := FileAccess.open(QUESTIONS_PATH, FileAccess.WRITE)
	if file == null:
		return "Cannot write %s (error %d). An exported build cannot save to res://." % [
			QUESTIONS_PATH, FileAccess.get_open_error()
		]
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return ""


func _normalise_board(board: Dictionary, number: int) -> Dictionary:
	var answers: Array[Dictionary] = []
	for entry: Variant in board.get("answers", []):
		var answer_text := str((entry as Dictionary).get("text", "")).strip_edges()
		var points := int((entry as Dictionary).get("points", 0))
		if answer_text.is_empty() or points <= 0:
			continue
		answers.append({"text": answer_text, "points": points})

	answers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("points", 0)) > int(b.get("points", 0))
	)

	return {
		"name": str(board.get("name", "Round %d" % number)).strip_edges(),
		"question": str(board.get("question", "")).strip_edges(),
		"answers": answers,
	}


func _blank_answers(count: int) -> Array[Dictionary]:
	var answers: Array[Dictionary] = []
	for i in count:
		answers.append({"text": "", "points": 10})
	return answers
