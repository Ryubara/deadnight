class_name GuestAccount
extends RefCounted
## What a visitor keeps to come back as the same Guest account (#1080). A guest has no Discord
## and no password: the backend's `POST /auth/guest` answers with `guestToken`, a signed
## credential good for 7 days, and the next sign-in sends it back and gets the same account (its
## saved XP, its saves), a fresh credential and 7 more days. This is the file the credential is
## kept in: `user://guest_account.json`, which on the web build is the browser's own storage
## (IndexedDB), on the desktop the game's user folder.
##
## One credential for each backend (a test backend, the live one), because each signs with its own
## secret. A credential nobody can read is no credential: the sign-in then makes a new guest. The
## file never holds anything but the credential; the name is the profile's.
##
## A test run, a capture and an agent's run keep nothing (`default_path` is empty, as the
## settings file's is, `SettingsService.default_path`), so a suite never reaches the file the
## person plays with, and a test that wants the file gives its own path.

const DEFAULT_PATH := "user://guest_account.json"
## No file: nothing is read and nothing is written.
const NO_FILE := ""
const VERSION := 1


## Where the credential is kept in this run (`NO_FILE` in a test run).
static func default_path() -> String:
	return NO_FILE if SettingsService.is_harness_run() else DEFAULT_PATH


## The credential kept for `backend`, or "" when there is none (no file, an unreadable one, none
## for this backend).
static func load_credential(backend: String, path: String = DEFAULT_PATH) -> String:
	return str(_read(path).get(_key(backend), ""))


## Keeps `credential` for `backend` (the one it replaces is gone). True when it was written; false
## when there is no file to write to. An empty credential forgets the backend's.
static func save_credential(
	backend: String, credential: String, path: String = DEFAULT_PATH
) -> bool:
	if path == NO_FILE:
		return false
	var accounts := _read(path)
	if credential == "":
		accounts.erase(_key(backend))
	else:
		accounts[_key(backend)] = credential
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": VERSION, "accounts": accounts}))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(path + ".tmp", path) == OK


## Forgets the credential of `backend`: the next sign-in is a new guest.
static func forget(backend: String, path: String = DEFAULT_PATH) -> void:
	save_credential(backend, "", path)


## The credentials in the file by backend; empty when there is no file or it cannot be read.
static func _read(path: String) -> Dictionary:
	if path == NO_FILE or not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	var accounts: Variant = (json.data as Dictionary).get("accounts")
	if not accounts is Dictionary:
		return {}
	var kept := {}
	for key: Variant in accounts:
		if key is String and accounts[key] is String:
			kept[key] = accounts[key]
	return kept


static func _key(backend: String) -> String:
	return backend.trim_suffix("/")
