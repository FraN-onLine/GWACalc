extends Control
class_name QuestionEditor
## Modal used to add or edit one question: its text plus a list of answers and points.
##
## Answer rows are built in code so the host can add or remove as many as the
## survey actually had - Family Feud boards are not limited to five.

signal saved(board: Dictionary)
signal cancelled

const MAX_ANSWERS := 12

@onready var _title_label: Label = %EditorTitle
@onready var _name_edit: LineEdit = %NameEdit
@onready var _question_edit: LineEdit = %QuestionEdit
@onready var _rows_box: VBoxContainer = %AnswerRows
@onready var _total_label: Label = %TotalLabel
@onready var _add_button: Button = %AddAnswerButton
@onready var _save_button: Button = %SaveButton
@onready var _cancel_button: Button = %CancelButton
@onready var _status_label: Label = %EditorStatus

var _rows: Array[Dictionary] = []


func _ready() -> void:
	_add_button.pressed.connect(_on_add_answer)
	_save_button.pressed.connect(_on_save)
	_cancel_button.pressed.connect(close)


## Opens the editor. Pass index == -1 to create a new question.
func open(board: Dictionary, index: int) -> void:
	_title_label.text = "EDIT QUESTION %d" % (index + 1) if index >= 0 else "NEW QUESTION"
	var fallback_name := "Question %d" % (index + 1) if index >= 0 else "New question"
	_name_edit.text = str(board.get("name", fallback_name))

	_question_edit.text = str(board.get("question", ""))
	_rows.clear()
	var answers: Array = board.get("answers", [])
	for entry: Variant in answers:
		_rows.append({
			"text": str((entry as Dictionary).get("text", "")),
			"points": int((entry as Dictionary).get("points", 0)),
		})
	if _rows.is_empty():
		for i in 5:
			_rows.append({"text": "", "points": 10})

	_rebuild_rows()
	_set_status("", false)
	visible = true
	_question_edit.grab_focus()


## Closes without saving. Used by CANCEL, by ESC and by the setup panel.
func close() -> void:
	visible = false
	cancelled.emit()


func _rebuild_rows() -> void:
	for child in _rows_box.get_children():
		child.queue_free()
		_rows_box.remove_child(child)

	for i in _rows.size():
		_rows_box.add_child(_make_row(i))

	_add_button.disabled = _rows.size() >= MAX_ANSWERS
	_update_total()


## Live check that the board adds up to the usual 100 survey points.
func _update_total() -> void:
	var total := 0
	var filled := 0
	for row: Dictionary in _rows:
		var points := int(row["points"])
		if not str(row["text"]).strip_edges().is_empty() and points > 0:
			total += points
			filled += 1

	_total_label.text = "%d answers  ·  %d points%s" % [
		filled, total, "" if total == 100 else "   (surveys usually total 100)"
	]
	_total_label.add_theme_color_override(
		"font_color", Color("8fb8ff") if total == 100 else Color("f1c40f")
	)


func _make_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var text_edit := LineEdit.new()
	text_edit.placeholder_text = "Answer %d" % (index + 1)
	text_edit.text = str(_rows[index]["text"])
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.text_changed.connect(_on_row_text_changed.bind(index))
	row.add_child(text_edit)

	var points_spin := SpinBox.new()
	points_spin.min_value = 0
	points_spin.max_value = 100
	points_spin.step = 1
	points_spin.value = int(_rows[index]["points"])
	points_spin.custom_minimum_size = Vector2(110, 0)
	points_spin.value_changed.connect(_on_row_points_changed.bind(index))
	row.add_child(points_spin)

	var remove_button := Button.new()
	remove_button.text = "✖"
	remove_button.custom_minimum_size = Vector2(52, 0)
	remove_button.tooltip_text = "Remove this answer"
	remove_button.pressed.connect(_on_remove_answer.bind(index))
	row.add_child(remove_button)

	return row


func _on_row_text_changed(value: String, index: int) -> void:
	_rows[index]["text"] = value
	_update_total()


func _on_row_points_changed(value: float, index: int) -> void:
	_rows[index]["points"] = int(value)
	_update_total()


func _on_remove_answer(index: int) -> void:
	if _rows.size() <= 1:
		return
	_rows.remove_at(index)
	_rebuild_rows()


func _on_add_answer() -> void:
	if _rows.size() >= MAX_ANSWERS:
		return
	_rows.append({"text": "", "points": 10})
	_rebuild_rows()


func _on_save() -> void:
	if _question_edit.text.strip_edges().is_empty():
		_set_status("The question text is required.", true)
		return

	var answers: Array[Dictionary] = []
	for row: Dictionary in _rows:
		var text := str(row["text"]).strip_edges()
		var points := int(row["points"])
		if text.is_empty() or points <= 0:
			continue
		answers.append({"text": text, "points": points})

	if answers.is_empty():
		_set_status("Add at least one answer with a text and some points.", true)
		return

	var board_name := _name_edit.text.strip_edges()
	if board_name.is_empty():
		board_name = "Question"

	_set_status("", false)
	visible = false
	saved.emit({
		"name": board_name,
		"question": _question_edit.text.strip_edges(),
		"answers": answers,
	})


func _set_status(text: String, is_error: bool) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override(
		"font_color", Color("ff6b6b") if is_error else Color("8fb8ff")
	)
