extends SceneTree
## Run by `test_capture_quit.gd` in a child Godot (not a test itself): the way a capture script uses
## a static test hook, then quits. It points the menu's board factory at a lambda of this script and
## clears it before `quit`; `--keep` leaves it set, the fault the test guards against (#667).
## The menu is loaded in the first frame: its script needs the autoloads, which exist only then.

const MENU := "res://ui/screens/main_menu.gd"
const BOARD := "res://tests/ui/fake_challenge_board.gd"


func _process(_delta: float) -> bool:
	var menu: GDScript = load(MENU)
	var board: GDScript = load(BOARD)
	menu.set("board_factory", func() -> Object: return board.new())
	if not OS.get_cmdline_user_args().has("--keep"):
		menu.set("board_factory", Callable())
	quit()
	return false
