@tool
extends EditorPlugin

## Editor entry point for dot-spectate. Registers inspector types only.
##
## No autoloads: a server deciding who may watch whom and a client mirroring one view
## are two of these in one process.

const _ICON := "res://addons/dot_spectate/icon_placeholder.svg"

const _TYPES := [
	[
		"DotSpectatorManager",
		"Node",
		"res://addons/dot_spectate/runtime/dot_spectator_manager.gd",
	],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
