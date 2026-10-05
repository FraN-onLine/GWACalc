extends Control
class_name MainMenu
## Title screen. Its only jobs are launching a game and explaining the controls.
##
##   START A GAME -> Game Setup (questions, teams, rules)
##   HOW TO PLAY  -> the help overlay drawn by this screen
##   QUIT         -> closes the game

signal play_requested
signal quit_requested

@onready var _play_button: Button = %PlayButton
@onready var _help_button: Button = %HelpButton
@onready var _quit_button: Button = %QuitButton
@onready var _matchup_label: Label = %MatchupLabel
@onready var _help_overlay: Control = %HelpOverlay
@onready var _help_close_button: Button = %HelpCloseButton


func _ready() -> void:
	_play_button.pressed.connect(_on_play)
	_help_button.pressed.connect(open_help)
	_quit_button.pressed.connect(func() -> void: quit_requested.emit())
	_help_close_button.pressed.connect(close_help)
	_help_overlay.visible = false


func _on_play() -> void:
	play_requested.emit()


## Shows the menu, always with the help overlay dismissed.
func open() -> void:
	close_help()
	refresh()
	visible = true


## Re-reads the team names so the menu always shows the current matchup.
func refresh() -> void:
	_matchup_label.text = "%s   vs   %s" % [GameData.teams[0], GameData.teams[1]]
	_play_button.grab_focus()


func open_help() -> void:
	_help_overlay.visible = true
	_help_close_button.grab_focus()


func close_help() -> void:
	_help_overlay.visible = false


func help_open() -> bool:
	return _help_overlay.visible
