extends Control
class_name ResultScreen
## Final scoreboard. Receives the summary dictionary emitted by GameScreen.game_finished.

signal play_again_requested
signal setup_requested
signal menu_requested

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _scores: Label = %Scores
@onready var _breakdown: Label = %Breakdown
@onready var _again_button: Button = %PlayAgainButton
@onready var _setup_button: Button = %SetupButton
@onready var _menu_button: Button = %MenuButton


func _ready() -> void:
	_again_button.pressed.connect(func() -> void: play_again_requested.emit())
	_setup_button.pressed.connect(func() -> void: setup_requested.emit())
	_menu_button.pressed.connect(func() -> void: menu_requested.emit())


func show_result(summary: Dictionary) -> void:
	var teams: Array = summary.get("teams", ["DCS", "DIT"])
	var scores: PackedInt32Array = summary.get("scores", PackedInt32Array([0, 0]))
	var winner := int(summary.get("winner", -1))
	var was_tiebreaker := bool(summary.get("was_tiebreaker", false))

	var team_a := str(teams[0])
	var team_b := str(teams[1])

	# Headline.
	if winner < 0:
		_title.text = "IT'S A TIE!"
		_title.add_theme_color_override("font_color", Color("f1c40f"))
		_subtitle.text = "Scores are level - the judges decide the victor."
	elif was_tiebreaker:
		_title.text = "%s WINS THE TIE-BREAKER!" % (team_a if winner == 0 else team_b)
		_title.add_theme_color_override("font_color", _color_for(winner))
		_subtitle.text = "Decided on the sudden-death board."
	else:
		_title.text = "%s WINS!" % (team_a if winner == 0 else team_b)
		_title.add_theme_color_override("font_color", _color_for(winner))
		var margin: int = absi(int(scores[0]) - int(scores[1]))
		_subtitle.text = "What a finish - %s points ahead." % margin

	_scores.text = "%s        %d     —     %d        %s" % [team_a, scores[0], scores[1], team_b]

	_breakdown.text = _build_breakdown(summary)
	_again_button.grab_focus()


## Running total after each round, plus a tie-breaker line when one was played.
func _build_breakdown(summary: Dictionary) -> String:
	var teams: Array = summary.get("teams", ["DCS", "DIT"])
	var lines: Array[String] = []
	lines.append("RUNNING TOTAL AFTER EACH ROUND")
	lines.append("")
	lines.append("%-22s %10s %10s" % ["", str(teams[0]), str(teams[1])])
	lines.append("------------------------------------------")

	for entry: Dictionary in summary.get("rounds", []):
		var scores: PackedInt32Array = entry.get("scores", PackedInt32Array([0, 0]))
		lines.append("%-22s %10d %10d" % [str(entry.get("name", "")), scores[0], scores[1]])

	if bool(summary.get("was_tiebreaker", false)):
		var tie_points: PackedInt32Array = summary.get("tie_points", PackedInt32Array([0, 0]))
		lines.append("")
		lines.append("Tie-breaker board: %s %d  -  %s %d" % [
			str(teams[0]), tie_points[0], str(teams[1]), tie_points[1]
		])
		lines.append("(tie-breaker points decide the winner only)")

	return "\n".join(lines)


func _color_for(team: int) -> Color:
	return Color("4ea3ff") if team == 0 else Color("ff8a5c")
