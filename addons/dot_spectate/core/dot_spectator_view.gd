class_name DotSpectatorView
extends RefCounted

## One viewer, and what they are looking at.
##
## [b]A mode and a target, and the camera falls out of the two.[/b] Source's observer
## modes are exactly this list and the numbering is kept because it is what twenty years
## of tooling, demos and server documentation says.

enum Mode {
	NONE,          ## Playing. Not watching anything.
	DEATH_CAM,     ## The moment after dying, on your own body.
	FREEZE_CAM,    ## Held on whoever killed you.
	FIXED,         ## A camera the map put somewhere.
	FIRST_PERSON,  ## Through a player's eyes.
	CHASE,         ## Behind them.
	ROAMING,       ## Anywhere.
}

var key: String = ""

var mode: Mode = Mode.NONE

## Who they are watching, "" when nobody or when roaming.
var target: String = ""

## Where a roaming camera is, and where it is looking.
var free_position: Vector3 = Vector3.ZERO
var free_basis: Basis = Basis.IDENTITY

## Which entry in the map's fixed camera list [constant Mode.FIXED] is using.
var fixed_index: int = 0

## The tick a timed mode ends on. -1 when it is not timed.
var until_tick: int = -1

## Where the viewer died, for the death camera. A death camera that follows a corpse
## into the floor is worse than one that does not move.
var death_position: Vector3 = Vector3.ZERO

## Who killed them, for the freeze camera.
var killer: String = ""


func _init(p_key: String = "") -> void:
	key = p_key


func is_watching() -> bool:
	return mode != Mode.NONE


## Whether this mode follows a player rather than a place.
func follows_target() -> bool:
	return mode == Mode.FIRST_PERSON or mode == Mode.CHASE or mode == Mode.FREEZE_CAM


func is_timed() -> bool:
	return until_tick >= 0


func describe() -> Dictionary:
	return {
		"key": key,
		"mode": Mode.keys()[mode],
		"target": target,
		"until": until_tick,
	}


func to_wire() -> Dictionary:
	return {
		"m": int(mode),
		"t": target,
		"p": free_position,
		"i": fixed_index,
		"u": until_tick,
		"k": killer,
	}


func apply_wire(w: Dictionary) -> void:
	mode = int(w.get("m", int(mode))) as Mode
	target = str(w.get("t", target))
	free_position = w.get("p", free_position)
	fixed_index = int(w.get("i", fixed_index))
	until_tick = int(w.get("u", until_tick))
	killer = str(w.get("k", killer))


func _to_string() -> String:
	return "DotSpectatorView(%s %s %s)" % [key, Mode.keys()[mode], target]
