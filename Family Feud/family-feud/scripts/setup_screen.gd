extends Control
class_name SetupScreen
## Game Setup - one page, nothing to scroll.
##
##   QUESTION BANK   tick the questions to play, and add / edit / copy / reorder / delete
##   TEAMS & RULES   the two team names plus every round rule
##   FOOTER          MAIN MENU (cancel)  and  START GAME (save, then play)
##
## The bank is the only thing that grows, so it is the only thing that scrolls -
## everything else is sized to fit the window.

signal start_requested(config: Dictionary)
signal closed
signal menu_requested

## One entry per question in the bank list.
class Row:
	var index: int = -1
	var container: HBoxContainer
	var toggle: CheckButton
	var meta: Label

var _rows: Array[Row] = []
## Tick state per question, held here so it survives an add / move / delete.
var _checked: Array[bool] = []
## True while the list is being rebuilt - building it must not look like an edit.
var _building: bool = false
## Question edits that have not been written to questions.json yet.
var _dirty: bool = false
## The question the editor is working on, or -1 when creating a brand new one.
var _editing_index: int = -1
## The question the toolbar buttons act on. Follows focus, so clicking a row selects it.
var _selected: int = -1

@onready var _question_list: VBoxContainer = %QuestionList
@onready var _select_all_button: Button = %SelectAllButton
@onready var _select_none_button: Button = %SelectNoneButton
@onready var _add_button: Button = %AddQuestionButton
@onready var _edit_button: Button = %EditQuestionButton
@onready var _copy_button: Button = %DuplicateQuestionButton
@onready var _delete_button: Button = %DeleteQuestionButton
@onready var _move_up_button: Button = %MoveUpButton
@onready var _move_down_button: Button = %MoveDownButton
@onready var _selection_label: Label = %SelectionLabel

@onready var _team_a_edit: LineEdit = %TeamAEdit
@onready var _team_b_edit: LineEdit = %TeamBEdit
@onready var _guesses_spin: SpinBox = %GuessesSpin
@onready var _strikes_spin: SpinBox = %StrikesSpin
@onready var _seconds_spin: SpinBox = %SecondsSpin
@onready var _columns_spin: SpinBox = %ColumnsSpin
@onready var _starter_option: OptionButton = %StarterOption
@onready var _tie_check: CheckButton = %TieCheck

@onready var _summary_label: Label = %SummaryLabel
@onready var _status_label: Label = %StatusLabel
@onready var _start_button: Button = %StartButton
@onready var _back_button: Button = %BackButton
@onready var _editor: QuestionEditor = %QuestionEditor
@onready var _delete_confirm: ConfirmationDialog = $DeleteConfirm

## Compact styleboxes shared by every bank row - see _build_row_styles().
var _row_styles: Dictionary = {}


func _ready() -> void:
	_select_all_button.pressed.connect(func() -> void: _set_all(true))
	_select_none_button.pressed.connect(func() -> void: _set_all(false))
	_add_button.pressed.connect(_on_add_question)
	_edit_button.pressed.connect(_on_edit_question)
	_copy_button.pressed.connect(_on_copy_question)
	_delete_button.pressed.connect(_on_delete_question)
	_move_up_button.pressed.connect(func() -> void: _on_move(-1))
	_move_down_button.pressed.connect(func() -> void: _on_move(1))
	_start_button.pressed.connect(_on_start_game)
	_back_button.pressed.connect(close)

	_delete_confirm.confirmed.connect(_on_delete_confirmed)
	_editor.saved.connect(_on_editor_saved)

	for spin: SpinBox in [_guesses_spin, _strikes_spin, _seconds_spin, _columns_spin]:
		spin.value_changed.connect(func(_v: float) -> void: _update_summary())
	_tie_check.toggled.connect(func(_v: bool) -> void: _update_summary())
	_starter_option.item_selected.connect(func(_i: int) -> void: _update_summary())
	_team_a_edit.text_changed.connect(func(_t: String) -> void: _on_team_name_changed())
	_team_b_edit.text_changed.connect(func(_t: String) -> void: _on_team_name_changed())

	_populate_fields()
	_build_row_styles()
	_sync_checked()
	_refresh_list()
	_update_summary()


## Bank rows keep the theme's button look but drop most of its padding. That is what
## lets a dozen questions fit the window without ever showing a scrollbar.
func _build_row_styles() -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.content_margin_left = 2.0
		box.content_margin_top = 3.0
		box.content_margin_right = 8.0
		box.content_margin_bottom = 3.0
		box.corner_radius_top_left = 6
		box.corner_radius_top_right = 6
		box.corner_radius_bottom_right = 6
		box.corner_radius_bottom_left = 6
		if state == "hover" or state == "pressed":
			box.bg_color = Color(1, 1, 1, 0.09)
		elif state == "focus":
			box.draw_center = false
			box.border_width_left = 2
			box.border_width_top = 2
			box.border_width_right = 2
			box.border_width_bottom = 2
			box.border_color = Color(0.945098, 0.768627, 0.054902, 0.9)
		_row_styles[state] = box


# ============================================================
# OPEN / CLOSE
# ============================================================

## Shows the panel. Pass a game config to carry the current teams and rules in.
func open(prefill: Dictionary = {}) -> void:
	_editor.visible = false
	if not prefill.is_empty():
		_apply_prefill(prefill)
	_sync_checked()
	_refresh_list()
	_update_summary()
	visible = true

	if _selected < 0 and GameData.round_count() > 0:
		_selected = 0
	_update_selection()
	_focus_selected()


func close() -> void:
	visible = false
	_editor.visible = false
	closed.emit()


func editor_open() -> bool:
	return _editor.visible


func close_editor() -> void:
	_editor.close()


# ============================================================
# TEAM + RULE FIELDS
# ============================================================

## Fills the team fields and rule widgets from the saved defaults.
func _populate_fields() -> void:
	_team_a_edit.text = GameData.teams[0]
	_team_b_edit.text = GameData.teams[1]

	_starter_option.clear()
	_starter_option.add_item("Team 1 first", 0)
	_starter_option.add_item("Team 2 first", 1)
	_starter_option.add_item("Alternate rounds", 2)

	_guesses_spin.value = int(GameData.rules.get("guesses_per_round", 10))
	_strikes_spin.value = int(GameData.rules.get("strikes_per_turn", 3))
	_seconds_spin.value = int(GameData.rules.get("seconds_per_guess", 0))
	_columns_spin.value = int(GameData.rules.get("answer_columns", 0))
	_tie_check.button_pressed = bool(GameData.rules.get("tie_breaker_enabled", true))
	_select_starter(int(GameData.rules.get("first_round_starter", 2)))
	_refresh_starter_labels()


## Overwrites the fields from a live game config so SETUP can be opened mid-show.
func _apply_prefill(config: Dictionary) -> void:
	var names: Variant = config.get("teams", null)
	if names is Array and (names as Array).size() >= 2:
		_team_a_edit.text = str(names[0])
		_team_b_edit.text = str(names[1])
	_guesses_spin.value = int(config.get("guesses_per_round", _guesses_spin.value))
	_strikes_spin.value = int(config.get("strikes_per_turn", _strikes_spin.value))
	_seconds_spin.value = int(config.get("seconds_per_guess", _seconds_spin.value))
	_columns_spin.value = int(config.get("answer_columns", _columns_spin.value))
	_tie_check.button_pressed = bool(config.get("tie_breaker_enabled", _tie_check.button_pressed))
	_select_starter(int(config.get("first_round_starter", _starter_value())))
	_refresh_starter_labels()


func _select_starter(value: int) -> void:
	for i in _starter_option.item_count:
		if _starter_option.get_item_id(i) == value:
			_starter_option.select(i)
			return
	_starter_option.select(0)


func _starter_value() -> int:
	var index := _starter_option.selected
	return 2 if index < 0 else _starter_option.get_item_id(index)


## Puts the real team names into the "first to answer" choices.
func _refresh_starter_labels() -> void:
	if _starter_option.item_count < 3:
		return
	_starter_option.set_item_text(0, "%s first" % _display_name(_team_a_edit.text, "Team 1"))
	_starter_option.set_item_text(1, "%s first" % _display_name(_team_b_edit.text, "Team 2"))
	_starter_option.set_item_text(2, "Alternate rounds")


func _on_team_name_changed() -> void:
	_refresh_starter_labels()
	_update_summary()


# ============================================================
# QUESTION BANK
# ============================================================

## Rebuilds every row from the current content.
func _refresh_list() -> void:
	_building = true
	for child in _question_list.get_children():
		_question_list.remove_child(child)
		child.queue_free()
	_rows.clear()

	for i in GameData.round_count():
		var row := _build_row(i)
		_rows.append(row)
		_question_list.add_child(row.container)

	_building = false


## One compact, fully clickable line: tick box, question text, then its stats.
func _build_row(index: int) -> Row:
	var board := GameData.get_round(index)
	var row := Row.new()
	row.index = index

	row.container = HBoxContainer.new()
	row.container.add_theme_constant_override("separation", 8)

	row.toggle = CheckButton.new()
	row.toggle.text = "%d.  %s" % [index + 1, str(board.get("question", "(no question yet)"))]
	row.toggle.tooltip_text = str(board.get("question", ""))
	row.toggle.clip_text = true
	row.toggle.custom_minimum_size = Vector2(0, 30)
	row.toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.toggle.add_theme_font_size_override("font_size", 15)
	for state: Variant in _row_styles:
		row.toggle.add_theme_stylebox_override(state, _row_styles[state])
	row.toggle.button_pressed = _checked[index]
	row.toggle.toggled.connect(_on_row_toggled.bind(index))
	row.toggle.focus_entered.connect(func() -> void: _select_row(index))
	row.container.add_child(row.toggle)

	row.meta = Label.new()
	row.meta.text = _board_meta(index)
	row.meta.custom_minimum_size = Vector2(175, 0)
	row.meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.meta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.meta.add_theme_color_override("font_color", Color("8f9bb3"))
	row.meta.add_theme_font_size_override("font_size", 13)
	row.container.add_child(row.meta)

	return row


## "8 answers  ·  100 pts" for one board.
func _board_meta(index: int) -> String:
	var answers: Array = GameData.get_round(index).get("answers", [])
	var total := 0
	for answer: Dictionary in answers:
		total += int(answer.get("points", 0))
	return "%d answers  ·  %d pts" % [answers.size(), total]


# --- ticks ------------------------------------------------------

## Keeps the tick array the same length as the bank, ticking anything new.
func _sync_checked() -> void:
	while _checked.size() < GameData.round_count():
		_checked.append(true)
	while _checked.size() > GameData.round_count():
		_checked.remove_at(_checked.size() - 1)


func _set_all(value: bool) -> void:
	_building = true
	for i in _checked.size():
		_checked[i] = value
	for row in _rows:
		row.toggle.button_pressed = value
	_building = false
	_update_summary()


func _on_row_toggled(pressed: bool, index: int) -> void:
	if _building or index < 0 or index >= _checked.size():
		return
	_checked[index] = pressed
	_update_summary()


## The ticked questions, in the order they will be played.
func _selected_indices() -> Array:
	var indices: Array = []
	for i in _checked.size():
		if _checked[i]:
			indices.append(i)
	return indices


## The tick boxes in bank order - handy for tests and for host scripts.
func toggles() -> Array[CheckButton]:
	var result: Array[CheckButton] = []
	for row in _rows:
		result.append(row.toggle)
	return result


# --- selection --------------------------------------------------

func _select_row(index: int) -> void:
	_selected = index
	_update_selection()


func _update_selection() -> void:
	var count := GameData.round_count()
	var has_selection := _selected >= 0 and _selected < count

	_edit_button.disabled = not has_selection
	_copy_button.disabled = not has_selection
	_delete_button.disabled = not has_selection
	_move_up_button.disabled = not has_selection or _selected <= 0
	_move_down_button.disabled = not has_selection or _selected >= count - 1

	if not has_selection:
		_selection_label.text = "Click a question to select it, then use the buttons underneath."
		return
	_selection_label.text = "SELECTED  %d.  %s" % [
		_selected + 1, str(GameData.get_round(_selected).get("question", ""))
	]


func _focus_selected() -> void:
	if _selected >= 0 and _selected < _rows.size():
		_rows[_selected].toggle.grab_focus()


# ============================================================
# ADD / EDIT / COPY / MOVE / DELETE
# ============================================================

func _on_add_question() -> void:
	_editing_index = -1
	_editor.open({"question": "", "answers": []}, -1)


func _on_edit_question() -> void:
	if _selected < 0:
		return
	_editing_index = _selected
	_editor.open(GameData.get_round(_selected), _selected)


func _on_copy_question() -> void:
	if _selected < 0:
		return
	var copy_index := GameData.duplicate_round(_selected)
	if copy_index == _selected:
		return
	_checked.insert(copy_index, _checked[_selected])
	_dirty = true
	_selected = copy_index
	_refresh_list()
	_update_selection()
	_update_summary()
	_focus_selected()


func _on_delete_question() -> void:
	if _selected < 0:
		return
	_delete_confirm.dialog_text = "Delete question %d from the bank?\n\n%s" % [
		_selected + 1, str(GameData.get_round(_selected).get("question", ""))
	]
	_delete_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	if _selected < 0:
		return
	var removed := _selected
	GameData.remove_round(removed)
	if removed < _checked.size():
		_checked.remove_at(removed)
	_dirty = true
	_selected = mini(removed, GameData.round_count() - 1)
	_refresh_list()
	_update_selection()
	_update_summary()
	_focus_selected()


func _on_move(offset: int) -> void:
	if _selected < 0:
		return
	var target := GameData.move_round(_selected, offset)
	if target == _selected:
		return
	var ticked: bool = _checked[_selected]
	_checked.remove_at(_selected)
	_checked.insert(target, ticked)
	_dirty = true
	_selected = target
	_refresh_list()
	_update_selection()
	_update_summary()
	_focus_selected()


## The editor closed with SAVE. index -1 in _editing_index meant "brand new".
func _on_editor_saved(board: Dictionary) -> void:
	var was_new := _editing_index < 0
	var index := GameData.update_round(_editing_index, board)
	_editing_index = -1
	_dirty = true
	_sync_checked()
	if was_new and index >= 0 and index < _checked.size():
		_checked[index] = true
	_selected = index
	_refresh_list()
	_update_selection()
	_update_summary()
	_focus_selected()


# ============================================================
# START THE GAME
# ============================================================

func _on_start_game() -> void:
	var name_a := _team_a_edit.text.strip_edges()
	var name_b := _team_b_edit.text.strip_edges()
	if name_a.is_empty() or name_b.is_empty():
		_set_status("Both teams need a name.", true)
		return
	if name_a.to_upper() == name_b.to_upper():
		_set_status("The two teams cannot share a name.", true)
		return

	var selected := _selected_indices()
	if selected.is_empty():
		_set_status("Tick at least one question to play.", true)
		return

	var overrides := {
		"guesses_per_round": int(_guesses_spin.value),
		"strikes_per_turn": int(_strikes_spin.value),
		"seconds_per_guess": int(_seconds_spin.value),
		"answer_columns": int(_columns_spin.value),
		"first_round_starter": _starter_value(),
		"tie_breaker_enabled": _tie_check.button_pressed,
	}

	if _dirty:
		var problem := GameData.save()
		if not problem.is_empty():
			_set_status("Could not save the questions: %s" % problem, true)
			return
		_dirty = false

	# Team names and rules are remembered, but only written when they change.
	if _settings_changed(name_a, name_b, overrides):
		var write_problem := GameData.save_settings(name_a, name_b, overrides)
		if not write_problem.is_empty():
			_set_status("Could not save the teams: %s" % write_problem, true)
			return

	var config := GameData.make_game_config({
		"teams": [name_a, name_b],
		"playlist": GameData.build_playlist(selected),
		"guesses_per_round": overrides["guesses_per_round"],
		"strikes_per_turn": overrides["strikes_per_turn"],
		"seconds_per_guess": overrides["seconds_per_guess"],
		"answer_columns": overrides["answer_columns"],
		"first_round_starter": overrides["first_round_starter"],
		"tie_breaker_enabled": _tie_check.button_pressed and GameData.tie_breaker_available(),
	})

	_set_status("", false)
	close()
	start_requested.emit(config)


## Only rewrites settings.json when something actually differs from the file.
func _settings_changed(name_a: String, name_b: String, overrides: Dictionary) -> bool:
	if name_a != GameData.teams[0] or name_b != GameData.teams[1]:
		return true
	for key: Variant in overrides:
		if int(GameData.rules.get(key, -1)) != int(overrides[key]):
			return true
	return false


# ============================================================
# SUMMARY + STATUS LINE
# ============================================================

## Keeps the header count and the status line in step with the ticks and fields.
func _update_summary() -> void:
	_summary_label.text = "%d of %d questions  ·  %s vs %s" % [
		_selected_indices().size(),
		GameData.round_count(),
		_display_name(_team_a_edit.text, "Team 1"),
		_display_name(_team_b_edit.text, "Team 2"),
	]

	if _dirty:
		_set_status("Question changes are not saved yet - they save when you press START GAME.", false)
	elif GameData.notices.size() > 0:
		_set_status("Note: " + "; ".join(GameData.notices), false)
	else:
		_set_status("", false)


func _display_name(value: String, fallback: String) -> String:
	var name := value.strip_edges()
	return fallback if name.is_empty() else name


func _set_status(text: String, is_error: bool) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override(
		"font_color", Color("ff6b6b") if is_error else Color("8fb8ff")
	)
