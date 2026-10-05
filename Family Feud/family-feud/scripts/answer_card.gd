extends PanelContainer
class_name AnswerCard
## One slot on the game board. Clicking it is how the host registers a correct guess.
##
## The card owns its own look and has two faces like the show's board: a big centred
## rank number while the answer is hidden, then the answer beside a gold points box
## once revealed. All styleboxes are built in code so AnswerCard.tscn stays a pure
## structure that is easy to re-skin or restyle.

signal card_pressed(card: AnswerCard)

## Column position in the board order, used for the printed 1..N number.
var index: int = -1
var answer_text: String = ""
var points: int = 0
var revealed: bool = false

var _clickable: bool = true

@onready var _hidden_number: Label = %HiddenNumber
@onready var _row: Container = %Row
@onready var _text_label: Label = %Text
@onready var _points_label: Label = %Points
@onready var _points_box: PanelContainer = %PointsBox
@onready var _button: Button = %CardButton

var _hidden_style: StyleBoxFlat
var _revealed_style: StyleBoxFlat
var _points_style: StyleBoxFlat


func _ready() -> void:
	_hidden_style = _make_style(Color("182848"), Color("3c6ec4"), 3)
	_revealed_style = _make_style(Color("1f5aa8"), Color("f1c40f"), 4)
	_points_style = _make_points_style()
	_points_box.add_theme_stylebox_override("panel", _points_style)
	_button.pressed.connect(_on_button_pressed)


## Configures the card. Always call this right after add_child().
func setup(new_index: int, answer: Dictionary) -> void:
	index = new_index
	answer_text = str(answer.get("text", ""))
	points = int(answer.get("points", 0))
	revealed = false
	_clickable = true

	_hidden_number.text = str(index + 1)
	_hidden_number.visible = true
	_row.visible = false
	_text_label.text = ""
	_points_label.text = ""

	add_theme_stylebox_override("panel", _hidden_style)
	modulate = Color.WHITE
	scale = Vector2.ONE
	_button.disabled = false
	_button.mouse_filter = Control.MOUSE_FILTER_STOP


## Flips the card over and plays a small pop.
func reveal() -> void:
	if revealed:
		return
	revealed = true
	_clickable = false

	_hidden_number.visible = false
	_row.visible = true
	_text_label.text = answer_text
	_points_label.text = str(points)
	add_theme_stylebox_override("panel", _revealed_style)
	_button.disabled = true
	_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

	pivot_offset = size * 0.5
	scale = Vector2(1.08, 1.08)
	modulate = Color(1, 1, 1, 0.25)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate", Color.WHITE, 0.25)
	tween.tween_property(self, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Greys the card out and stops it accepting clicks (used outside the playing phase).
func lock() -> void:
	_clickable = false
	_button.disabled = true
	_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate = Color(0.72, 0.75, 0.82, 1.0)


func is_revealed() -> bool:
	return revealed


func _on_button_pressed() -> void:
	if not _clickable or revealed:
		return
	card_pressed.emit(self)


func _make_style(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 3)
	return style


## The gold plaque beside a revealed answer: big dark number on solid gold, like the show.
func _make_points_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f1c40f")
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6)
	return style
