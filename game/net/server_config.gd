class_name ServerConfig
extends RefCounted
## What a game server that works with the platform backend is told through environment variables
## (Railway service variables), and nothing else: with no `BACKEND_URL` it is the single-night
## server of `NightHost`, as on a developer's machine.
##
##   BACKEND_URL         https address of the backend (no trailing slash)
##   GAME_SERVER_SECRET  what the server calls the backend's /internal routes with
##   TICKET_SECRET       what the backend signs tickets with (never sent anywhere)
##   SERVER_ID           the name the backend knows this server by (default: the Railway service id)
##   PUBLIC_URL          where players connect (default: wss:// the Railway public domain)
##   ACTIVITY_PATH       the Discord proxy path mapped to this server (default /server)
##   ROOM_CAPACITY       nights one process takes (default 3)
##   MAX_ALIVE           the most zombies alive at once in any night of this process (default: the
##                       rules', 120 for desktop players and 40 with a browser in the match); the
##                       process's CPU is shared by its rooms, so a small container takes less
##   ALIVE_BUDGET        the most zombies alive at once in all the nights of this process together
##                       (default 120): each night is cut to its share, 0 turns it off
##   MAX_BOTS            the most bots one room seats, 0 to 3 (default 3): the host's Bots setting
##                       can ask for fewer, never more
##   BOTS_OFF            1, true, yes or on: the kill-switch, no room seats a bot and the bots
##                       standing leave (default off)
##   BOT_BUDGET          the most bots in all the rooms of this process together (default 0: none);
##                       each room is cut to its share of it

var backend_url := ""
var game_server_secret := ""
var ticket_secret := ""
var server_id := ""
var public_url := ""
var activity_path := "/server"
var capacity := GameServer.DEFAULT_CAPACITY
## 0 is no cap beyond the rules' own.
var max_alive := 0
var alive_budget := GameServer.DEFAULT_ALIVE_BUDGET
var max_bots := MatchSettings.MAX_BOTS
var bots_off := false
## 0 is no budget.
var bot_budget := 0


## Reads `getenv` (a Callable name -> String; `OS.get_environment` by default).
static func from_environment(getenv: Callable = Callable()) -> ServerConfig:
	var read: Callable = getenv if getenv.is_valid() else Callable(OS, "get_environment")
	var config := ServerConfig.new()
	config.backend_url = str(read.call("BACKEND_URL")).strip_edges().trim_suffix("/")
	config.game_server_secret = read.call("GAME_SERVER_SECRET")
	config.ticket_secret = read.call("TICKET_SECRET")
	var service: String = read.call("RAILWAY_SERVICE_ID")
	config.server_id = _or(
		read.call("SERVER_ID"), "gs-" + service.left(12) if service != "" else "gs-local"
	)
	var domain: String = read.call("RAILWAY_PUBLIC_DOMAIN")
	config.public_url = _or(read.call("PUBLIC_URL"), "wss://" + domain if domain != "" else "")
	config.activity_path = _or(read.call("ACTIVITY_PATH"), "/server")
	var rooms := int(str(read.call("ROOM_CAPACITY")))
	config.capacity = rooms if rooms > 0 else GameServer.DEFAULT_CAPACITY
	config.max_alive = maxi(int(str(read.call("MAX_ALIVE"))), 0)
	var budget := str(read.call("ALIVE_BUDGET")).strip_edges()
	config.alive_budget = maxi(int(budget), 0) if budget.is_valid_int() else config.alive_budget
	var cap := str(read.call("MAX_BOTS")).strip_edges()
	config.max_bots = (
		clampi(int(cap), 0, MatchSettings.MAX_BOTS) if cap.is_valid_int() else config.max_bots
	)
	config.bots_off = (
		str(read.call("BOTS_OFF")).strip_edges().to_lower() in ["1", "true", "yes", "on"]
	)
	config.bot_budget = maxi(int(str(read.call("BOT_BUDGET"))), 0)
	return config


## Whether this server takes its nights from the backend (it has a backend to ask and a secret to
## check tickets with).
func uses_backend() -> bool:
	return backend_url != "" and ticket_secret.length() >= 32 and game_server_secret.length() >= 32


## Why it cannot (for the log), or an empty string.
func problem() -> String:
	if backend_url == "":
		return ""
	if ticket_secret.length() < 32:
		return "TICKET_SECRET is missing or shorter than 32 characters"
	if game_server_secret.length() < 32:
		return "GAME_SERVER_SECRET is missing or shorter than 32 characters"
	return ""


static func _or(value: Variant, fallback: String) -> String:
	var text := str(value)
	return text if text != "" else fallback
