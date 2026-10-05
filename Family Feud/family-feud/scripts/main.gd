extends Control
class_name Main
## Root scene. Owns nothing but navigation, so exactly one screen is on show at a time.
##
##   MainMenu  --START A GAME-->  SetupScreen  --START GAME-->  GameScreen
##   GameScreen  --END OF GAME-->  ResultScreen  --PLAY AGAIN-->  GameScreen
##   Anything  --ESC / MAIN MENU-->  SetupScreen / MainMenu
##
## The setup panel is the only screen that can sit on top of another one, so the
## host can change the questions without losing a game in progress.

@onready var _menu: MainMenu = %MainMenu
@onready var _setup: SetupScreen = %SetupScreen
@onready var _game: GameScreen = %GameScreen
@onready var _result: ResultScreen = %ResultScreen

## True once a game has been started, so SETUP can prefill from the last one played.
var _has_game: bool = false
var _last_config: Dictionary = {}
## Which screen opened the setup panel: "menu", "game" or "result". Cancelling
## returns there, so PLAY -> BACK never drops you onto a stale board.
var _setup_return: String = "menu"


func _ready() -> void:
	_menu.play_requested.connect(func() -> void: open_setup())
	_menu.quit_requested.connect(get_tree().quit)

	_setup.start_requested.connect(_start_game)
	_setup.closed.connect(_on_setup_closed)
	_setup.menu_requested.connect(show_menu)

	_game.game_finished.connect(_on_game_finished)
	_game.request_setup.connect(func() -> void: open_setup(_last_config))

	_result.play_again_requested.connect(_on_play_again)
	_result.setup_requested.connect(func() -> void: open_setup(_last_config))
	_result.menu_requested.connect(show_menu)

	show_menu()


# ============================================================
# SCREENS
# ============================================================

func show_menu() -> void:
	_menu.open()
	_setup.visible = false
	_game.visible = false
	_result.visible = false


## Opens the setup panel on its own. Pass a game config to carry the current
## teams and rules in; without one the last played game is used when there is one.
func open_setup(prefill: Dictionary = {}) -> void:
	# Remember what is underneath before it gets hidden.
	if _game.visible:
		_setup_return = "game"
	elif _result.visible:
		_setup_return = "result"
	else:
		_setup_return = "menu"

	var fields: Dictionary = prefill
	if fields.is_empty() and _has_game:
		fields = _last_config

	_menu.visible = false
	_game.visible = false
	_result.visible = false
	_setup.visible = true
	_setup.open(fields)


## Cancelled out of setup - go back to the screen that opened it.
func _on_setup_closed() -> void:
	match _setup_return:
		"game":
			_game.visible = true
		"result":
			_result.visible = true
		_:
			show_menu()


func _start_game(config: Dictionary) -> void:
	_last_config = config.duplicate(true)
	_has_game = true
	_menu.visible = false
	_setup.visible = false
	_result.visible = false
	_game.visible = true
	_game.start_game(_last_config)


func _on_game_finished(summary: Dictionary) -> void:
	_menu.visible = false
	_setup.visible = false
	_game.visible = false
	_result.visible = true
	_result.show_result(summary)


## Same teams, same questions, brand new game.
func _on_play_again() -> void:
	if _last_config.is_empty():
		open_setup()
		return
	_start_game(_last_config)


# ============================================================
# ESC  -  one key, one extra layer, never a surprise
# ============================================================

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_ESCAPE:
		return

	if _menu.visible:
		if _menu.help_open():
			_menu.close_help()
			get_viewport().set_input_as_handled()
		return

	if _setup.visible:
		# ESC closes the question editor first, then the whole panel.
		if _setup.editor_open():
			_setup.close_editor()
		else:
			_setup.close()
		get_viewport().set_input_as_handled()
		return

	if _game.visible:
		open_setup(_last_config)
		get_viewport().set_input_as_handled()
