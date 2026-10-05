extends Control
class_name GameScreen
## The actual show: one board per round, teams alternating every guess, points awarded
## when the host clicks a correct answer, and everything accumulated across the rounds.
##
## Every rule the host can change lives in _config, which comes straight from
## GameData.make_game_config() after SetupScreen merged in its overrides.

signal game_finished(summary: Dictionary)
signal request_setup

const CARD_SCENE := preload("res://scenes/AnswerCard.tscn")

enum Phase { PLAYING, REVEALING, ROUND_DONE, FINISHED }

var _config: Dictionary = {}
var _teams: Array[String] = ["DCS", "DIT"]

## Running totals across every round played.
var _scores: PackedInt32Array = PackedInt32Array([0, 0])
## One entry per finished round: { "name": String, "scores": PackedInt32Array, "round": int }.
var _round_log: Array[Dictionary] = []

var _phase: int = Phase.FINISHED
var _round_index: int = 0
var _turn: int = 0
var _guesses_used: int = 0
var _strikes: int = 0
var _cards: Array[AnswerCard] = []
var _timer_running: bool = false
var _time_left: float = 0.0
var _strike_tween: Tween = null

## What the between-boards score panel does when its button is pressed, plus its label.
var _break_action: Callable = Callable()
var _break_button_text: String = "NEXT QUESTION  ▶"

## How long the finished board lingers before the score panel appears, so the last
## reveal is never covered mid-pop. Tests may set this to 0.0 for instant panels.
var break_pause: float = 1.5
var _pending_break_title: String = ""
var _break_timer: Timer

## Tie-breaker bookkeeping, kept apart so it never pollutes the regular totals.
var _in_tiebreaker: bool = false
var _tie_points: PackedInt32Array = PackedInt32Array([0, 0])

@onready var _round_label: Label = %RoundLabel
@onready var _question_label: Label = %QuestionLabel
@onready var _turn_label: Label = %TurnLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _status_label: Label = %StatusLabel
@onready var _strike_label: Label = %StrikeLabel
@onready var _guesses_label: Label = %GuessesLabel

@onready var _team_a_name: Label = %TeamAName
@onready var _team_a_score: Label = %TeamAScore
@onready var _team_b_name: Label = %TeamBName
@onready var _team_b_score: Label = %TeamBScore

@onready var _board: GridContainer = %AnswerGrid
@onready var _strike_x: Control = %StrikeX
@onready var _strike_x_label: Label = %StrikeXLabel
@onready var _timer: Timer = %TurnTimer

@onready var _btn_a: Button = %TeamAButton
@onready var _btn_b: Button = %TeamBButton
@onready var _miss_button: Button = %MissButton
@onready var _reveal_button: Button = %RevealButton
@onready var _skip_button: Button = %SkipButton
@onready var _menu_button: Button = %MenuButton

@onready var _round_break: Control = %RoundBreak
@onready var _break_title: Label = %BreakTitle
@onready var _break_team_a_name: Label = %BreakTeamAName
@onready var _break_team_a_score: Label = %BreakTeamAScore
@onready var _break_team_b_name: Label = %BreakTeamBName
@onready var _break_team_b_score: Label = %BreakTeamBScore
@onready var _break_next_button: Button = %BreakNextButton


func _ready() -> void:
	_break_timer = Timer.new()
	_break_timer.one_shot = true
	_break_timer.timeout.connect(_on_break_timer_timeout)
	add_child(_break_timer)

	_btn_a.pressed.connect(_on_team_button.bind(0))
	_btn_b.pressed.connect(_on_team_button.bind(1))
	_miss_button.pressed.connect(_on_miss_pressed)
	_reveal_button.pressed.connect(_on_reveal_pressed)
	_skip_button.pressed.connect(_on_skip_pressed)
	_break_next_button.pressed.connect(_on_break_next_pressed)
	_menu_button.pressed.connect(func() -> void: request_setup.emit())
	_timer.timeout.connect(_on_timer_timeout)


func _process(delta: float) -> void:
	if not _timer_running:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	_refresh_timer_label()


## Starts a fresh game. Safe to call again for "play again".
func start_game(config: Dictionary) -> void:
	_config = config.duplicate(true)
	_teams = [str(_config["teams"][0]), str(_config["teams"][1])]

	_scores = PackedInt32Array([0, 0])
	_round_log.clear()
	_in_tiebreaker = false
	_tie_points = PackedInt32Array([0, 0])

	_team_a_name.text = _teams[0]
	_team_b_name.text = _teams[1]

	_begin_round(0)


# ============================================================
# ROUND FLOW
# ============================================================

## Plays one of the boards the host ticked, in order, straight after the other.
func _begin_round(round_index: int) -> void:
	_round_index = round_index
	_in_tiebreaker = false
	_round_break.visible = false
	_break_timer.stop()
	var boards: Array = _config.get("rounds", [])
	if round_index < 0 or round_index >= boards.size():
		push_error("No board at playlist position %d." % round_index)
		_finish_game()
		return

	_load_board(boards[round_index])
	_turn = GameData.starter_for_round(round_index, int(_config.get("first_round_starter", 2)))
	_set_status("Read the question, then click an answer when a team guesses correctly.")


## Builds the cards for a board definition and resets the per-round counters.
## Shared by regular rounds and by the tie-breaker.
func _load_board(board: Dictionary) -> void:
	if board.is_empty():
		push_error("No board data for round %d." % (_round_index + 1))
		_finish_game()
		return

	var answers: Array = board.get("answers", [])
	_clear_board()
	# A strike flash must never carry over into the next board.
	if _strike_tween != null and _strike_tween.is_running():
		_strike_tween.kill()
	_strike_x.visible = false
	_board.columns = _columns_for(answers.size())

	# Build the cards in logical order first, then hand them to the grid in
	# column-major order so the board reads down each column:
	#   1 5
	#   2 6
	#   3 7
	#   4 8
	var cards: Array[AnswerCard] = []
	for i in answers.size():
		var card := CARD_SCENE.instantiate() as AnswerCard
		cards.append(card)
		_cards.append(card)

	for idx in _column_major_order(cards.size(), _board.columns):
		var card := cards[idx]
		_board.add_child(card)
		card.setup(idx, answers[idx])
		card.card_pressed.connect(_on_card_pressed)

	_round_label.text = str(board.get("name", "Round")).to_upper()
	_question_label.text = str(board.get("question", ""))
	_guesses_used = 0
	_strikes = 0
	_phase = Phase.PLAYING
	_start_turn_timer()
	_refresh()


## 2 columns suits the classic Family Feud look and fits an 8-answer board
## comfortably; wider boards (more than 8 answers) switch to 3.
func _columns_for(answer_count: int) -> int:
	var configured := int(_config.get("answer_columns", 0))
	if configured > 0:
		return configured
	return 2 if answer_count <= 8 else 3


## The order the cards have to be handed to the grid, which fills row by row.
## For eight answers in two columns that is 1,5,2,6,3,7,4,8 - so the board
## reads down the first column, then the next. The printed number on each card
## comes from its own index, so it still runs 1..N.
func _column_major_order(count: int, columns: int) -> Array[int]:
	var per_column := ceili(float(count) / float(maxi(columns, 1)))
	var order: Array[int] = []
	for row in per_column:
		for col in columns:
			var idx := col * per_column + row
			if idx < count:
				order.append(idx)
	return order


func _max_guesses() -> int:
	return maxi(1, int(_config.get("guesses_per_round", 10)))


func _max_strikes() -> int:
	return maxi(1, int(_config.get("strikes_per_turn", 3)))




# ============================================================
# ANSWERING
# ============================================================

## The host clicked an answer card: the team currently answering guessed correctly.
func _on_card_pressed(card: AnswerCard) -> void:
	if _phase != Phase.PLAYING or card.is_revealed():
		return

	card.reveal()
	_guesses_used += 1

	if _in_tiebreaker:
		_tie_points[_turn] += card.points
	else:
		_scores[_turn] += card.points

	_stop_timer()
	_set_status("%s scored %d points!" % [_teams[_turn], card.points])
	_refresh()

	if _all_revealed() or _guesses_used >= _max_guesses():
		_finish_round()
		return

	# Teams alternate after every guess so neither side owns the whole round.
	_switch_turn()


## The host pressed "wrong answer": that is a strike, and it costs a guess slot.
func _on_miss_pressed() -> void:
	if _phase != Phase.PLAYING:
		return

	_guesses_used += 1
	_strikes += 1
	_play_strike_x()
	_stop_timer()
	_refresh()

	if _strikes >= _max_strikes():
		_set_status("%s used all their strikes - turn passes." % _teams[_turn])
		_strikes = 0
		_refresh()
		_switch_turn()
		return

	_set_status("Wrong answer. %s has %d strike%s." % [
		_teams[_turn], _strikes, "" if _strikes == 1 else "s"
	])

	if _guesses_used >= _max_guesses():
		_finish_round()


## The host pressed a team button to decide who answers next.
func _on_team_button(team: int) -> void:
	if _phase != Phase.PLAYING or team == _turn:
		return
	_switch_turn()
	_set_status("%s now answers. Strikes reset." % _teams[team])


func _switch_turn() -> void:
	_turn = 1 - _turn
	_strikes = 0
	_start_turn_timer()
	_refresh()


func _all_revealed() -> bool:
	return _unrevealed_count() == 0


func _unrevealed_count() -> int:
	var count := 0
	for card in _cards:
		if not card.is_revealed():
			count += 1
	return count



# ============================================================
# TURN TIMER  (only runs when seconds_per_guess > 0)
# ============================================================

func _start_turn_timer() -> void:
	var seconds := int(_config.get("seconds_per_guess", 0))
	if seconds <= 0 or _phase != Phase.PLAYING:
		_stop_timer()
		return
	_time_left = float(seconds)
	_timer.wait_time = float(seconds)
	_timer.start()
	_timer_running = true
	_refresh_timer_label()


func _stop_timer() -> void:
	_timer.stop()
	_timer_running = false
	_time_left = 0.0
	_refresh_timer_label()


func _on_timer_timeout() -> void:
	if _phase != Phase.PLAYING:
		return
	_timer_running = false
	_set_status("Time is up for %s - turn passes." % _teams[_turn])
	_switch_turn()


func _refresh_timer_label() -> void:
	if not _timer_running:
		_timer_label.text = "--"
		_timer_label.add_theme_color_override("font_color", Color("6b7a99"))
		return
	_timer_label.text = "%d" % int(ceil(_time_left))
	_timer_label.add_theme_color_override(
		"font_color", Color("ff6b6b") if _time_left <= 3.0 else Color("f1c40f")
	)



# ============================================================
# END OF ROUND
# ============================================================

func _finish_round() -> void:
	if _phase == Phase.REVEALING or _phase == Phase.ROUND_DONE:
		return

	_phase = Phase.REVEALING
	_stop_timer()
	for card in _cards:
		card.lock()

	_round_log.append({
		"name": _round_label.text,
		"scores": _scores.duplicate(),
		"round": _round_index + 1,
	})

	var remaining := _unrevealed_count()
	if remaining == 0:
		_close_round()
	else:
		_set_status("Round over. Reveal the remaining %d answer%s one by one." % [
			remaining, "" if remaining == 1 else "s"
		])
	_refresh()


## Reveals exactly ONE hidden card - this is the "one by one" rule (guideline 6).
func _on_reveal_pressed() -> void:
	if _phase != Phase.REVEALING:
		return

	for card in _cards:
		if not card.is_revealed():
			card.reveal()
			var left := _unrevealed_count()
			if left > 0:
				_set_status("%d answer%s still hidden." % [left, "" if left == 1 else "s"])
			else:
				_close_round()
			_refresh()
			return

	_close_round()
	_refresh()


## Host shortcut: end the round early, or dump the rest of the board at once.
func _on_skip_pressed() -> void:
	if _phase == Phase.PLAYING:
		_finish_round()
		return
	if _phase == Phase.REVEALING:
		while _phase == Phase.REVEALING:
			_on_reveal_pressed()


func _close_round() -> void:
	if _phase == Phase.ROUND_DONE:
		return
	_phase = Phase.ROUND_DONE
	for card in _cards:
		card.reveal()
	_stop_timer()

	# Work out what comes next, then pause on a calm scoreboard panel so the host
	# always sees both totals before the next board (or the results) loads.
	if _in_tiebreaker:
		_break_button_text = "SEE RESULTS  ▶"
		_break_action = _finish_game
		_set_status("Tie-breaker complete.")
		_queue_round_break("TIE-BREAKER COMPLETE")
		return

	if _is_last_round():
		_break_button_text = "SEE RESULTS  ▶"
		_break_action = _finish_game
		# Guideline 11: level totals after the last round go to a tie-breaker board.
		if _scores[0] == _scores[1] and bool(_config.get("tie_breaker_enabled", false)):
			_break_button_text = "NEXT QUESTION  ▶"
			_break_action = _start_tiebreaker
		_set_status("All boards played.")
		_queue_round_break("FINAL ROUND COMPLETE")
		return

	_break_button_text = "NEXT QUESTION  ▶"
	_break_action = _begin_round.bind(_round_index + 1)
	_set_status("Round %d done." % (_round_index + 1))
	_queue_round_break("ROUND %d COMPLETE" % (_round_index + 1))


## True when the round just finished is the last one the host asked to play.
func _is_last_round() -> bool:
	return _round_index + 1 >= _total_rounds()


## How many boards are in this game. Totals carry across all of them.
func _total_rounds() -> int:
	return maxi(1, int(_config.get("round_count", _config.get("rounds", []).size())))


## Shows the between-boards panel: just the two teams, their totals and one button.
func _show_round_break(title: String) -> void:
	_break_title.text = title
	_break_team_a_name.text = _teams[0]
	_break_team_b_name.text = _teams[1]
	_break_team_a_score.text = str(_scores[0])
	_break_team_b_score.text = str(_scores[1])
	_break_next_button.text = _break_button_text
	_round_break.visible = true


## The finished board holds for a beat before the panel slides over it: the answer
## just revealed needs its moment on screen (the card's own pop takes a quarter of
## a second). Starting a new game during the pause cancels the pending panel.
func _queue_round_break(title: String) -> void:
	_pending_break_title = title
	if break_pause <= 0.0:
		_show_round_break(title)
		return
	_break_timer.start(break_pause)


func _on_break_timer_timeout() -> void:
	if _phase != Phase.ROUND_DONE:
		return  # a new game started during the pause - drop the stale panel
	_show_round_break(_pending_break_title)


## Continues whatever the panel queued up: the next question, the tie-breaker or the results.
func _on_break_next_pressed() -> void:
	if _phase != Phase.ROUND_DONE:
		return

	_round_break.visible = false
	var action := _break_action
	_break_action = Callable()
	if action.is_valid():
		action.call()



# ============================================================
# TIE-BREAKER
# ============================================================

## Points earned here decide the winner only - they are never added to the totals.
func _start_tiebreaker() -> void:
	var board := GameData.tie_breaker
	if board.is_empty():
		_finish_game()
		return

	_in_tiebreaker = true
	_tie_points = PackedInt32Array([0, 0])
	_turn = 1 - _turn  # whoever did not start the last round goes first
	_load_board(board)
	_set_status("TIE-BREAKER! %s answers first. These points do not count towards the total." % _teams[_turn])


func _tie_winner() -> int:
	if _tie_points[0] > _tie_points[1]:
		return 0
	if _tie_points[1] > _tie_points[0]:
		return 1
	return -1



# ============================================================
# FINISH
# ============================================================

func _finish_game() -> void:
	_phase = Phase.FINISHED
	_round_break.visible = false
	_stop_timer()
	for card in _cards:
		card.lock()

	var winner := _tie_winner() if _in_tiebreaker else _winner_from_scores()
	game_finished.emit({
		"teams": _teams.duplicate(),
		"scores": _scores.duplicate(),
		"rounds": _round_log.duplicate(true),
		"winner": winner,
		"was_tiebreaker": _in_tiebreaker,
		"tie_points": _tie_points.duplicate(),
	})


func _winner_from_scores() -> int:
	if _scores[0] > _scores[1]:
		return 0
	if _scores[1] > _scores[0]:
		return 1
	return -1


func _clear_board() -> void:
	for card in _cards:
		if is_instance_valid(card):
			card.queue_free()
	_cards.clear()



# ============================================================
# UI
# ============================================================

## Stamps a huge X over the whole screen every time a team misses, the way the
## show does, then gets out of the way again after about a second.
func _play_strike_x() -> void:
	if _strike_tween != null and _strike_tween.is_running():
		_strike_tween.kill()

	_strike_x.pivot_offset = _strike_x.size * 0.5
	_strike_x.scale = Vector2(1.8, 1.8)
	_strike_x.modulate = Color(1, 1, 1, 0.0)
	_strike_x.visible = true

	_strike_tween = create_tween()
	_strike_tween.tween_property(_strike_x, "modulate:a", 1.0, 0.08)
	_strike_tween.parallel().tween_property(_strike_x, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_strike_tween.tween_interval(0.5)
	_strike_tween.tween_property(_strike_x, "modulate:a", 0.0, 0.3)
	_strike_tween.tween_callback(_hide_strike_x)


func _hide_strike_x() -> void:
	if is_instance_valid(_strike_x):
		_strike_x.visible = false


func _refresh() -> void:
	_team_a_score.text = str(_scores[0])
	_team_b_score.text = str(_scores[1])

	_turn_label.text = "ANSWERING: %s" % _teams[_turn]
	_turn_label.add_theme_color_override("font_color", _team_color(_turn))

	_guesses_label.text = "GUESSES: %d / %d" % [_guesses_used, _max_guesses()]
	_strike_label.text = _strike_text()

	var playing := _phase == Phase.PLAYING
	_btn_a.disabled = not playing
	_btn_b.disabled = not playing
	_miss_button.disabled = not playing

	_reveal_button.visible = _phase == Phase.REVEALING
	_skip_button.visible = playing or _phase == Phase.REVEALING


func _strike_text() -> String:
	var text := ""
	for i in _max_strikes():
		if i > 0:
			text += "   "
		text += "[X]" if i < _strikes else "[  ]"
	return "%s  %s" % [_teams[_turn], text]


func _team_color(team: int) -> Color:
	return Color("4ea3ff") if team == 0 else Color("ff8a5c")


func _set_status(text: String) -> void:
	_status_label.text = text

