@tool
class_name DotSpectatorRules
extends DotConfig

## Every policy about watching, in one layered configuration.
##
## [b]Spectating is a competitive-integrity system before it is a camera.[/b] Almost
## everything here exists because somebody used a spectator camera to cheat: a dead
## player calling out positions, a streamer's viewers reading the map, a teammate on a
## second monitor. The camera part is four lines; the rest is who may see what.

## Emitted when a cvar changed a rule, so a client can leave a roam the server just
## forbade.
signal rules_changed

@export_group("Who may watch whom")

## 0 anybody, 1 own team only, 2 nobody.
##
## [code]mp_forcecamera[/code], and the numbering is deliberately the one server
## operators already type from memory. "Own team only" also forces first
## person, because a chase camera behind a team-mate sees round corners they cannot.
##
## Zero by default since free-roaming is on by default (2026-10-21): roaming and a
## restricted camera cannot both hold, and the restriction is the one an operator opts
## into with [code]mp_forcecamera 1[/code]. A team game that wants the competitive
## default sets it in its own rules and then gets no roaming, by [method roaming_permitted].
@export_enum("all", "team", "none") var force_camera: int = 0

## Whether a dead player may watch at all before the round ends.
@export var allow_while_dead: bool = true

## Whether a player who has not joined a side may watch.
@export var allow_unassigned: bool = true

## Whether a live player may spectate. Off, obviously, and the setting exists because a
## replay viewer and a demo playback are both live processes with nobody playing.
@export var allow_while_alive: bool = false

## Whether free-roaming is offered.
##
## On by default. Only takes effect with [member force_camera] "all": a roaming camera goes
## anywhere, which is the whole problem the restriction is for, so the two are never both
## true — see [method roaming_permitted]. [code]mp_freeroam[/code].
@export var allow_roaming: bool = true

## How fast a roaming camera flies, in metres a second.
## [code]mp_freeroam_speed[/code].
@export_range(0.5, 200.0, 0.5, "or_greater") var roam_speed: float = 12.0

## What the fast key multiplies [member roam_speed] by, and what the slow key does.
@export_range(1.0, 20.0, 0.1, "or_greater") var roam_fast_scale: float = 3.0
@export_range(0.05, 1.0, 0.05) var roam_slow_scale: float = 0.25

@export_group("Cameras")

## Ticks the death camera holds on the body before anything else happens.
@export_range(0, 100000, 1) var death_cam_ticks: int = 128

## Ticks the freeze camera holds on the killer afterwards. Zero skips it.
@export_range(0, 100000, 1) var freeze_cam_ticks: int = 192

## How far behind a target the chase camera sits.
@export_range(0.1, 100.0, 0.1, "or_greater") var chase_distance: float = 3.5

## How far above them.
@export_range(-10.0, 100.0, 0.1, "or_greater") var chase_height: float = 0.8

## What the camera does when its target dies or leaves.
##
## On, and it is not a nicety: a spectator whose target disconnects is looking at
## nothing, with no input that obviously fixes it, and reports it as the game freezing.
@export var auto_retarget: bool = true

## Whether the cycle order includes dead players.
@export var cycle_includes_dead: bool = false

@export_group("Delay")

## Ticks of delay between what happens and what a spectator sees.
##
## [b]This is the anti-stream-sniping setting and it is the reason this addon keeps a
## history at all.[/b] A spectator watching live is a live intelligence feed: a player
## on a second machine, a streamer's chat, a teammate who died first. A broadcast relay's
## answer is ninety seconds and a competitive server's is a few; either way the camera
## samples a tick in the past and the whole rest of the addon does not have to know.
##
## Zero is live, which is what a suite and a single-player replay want.
@export_range(0, 100000, 1) var delay_ticks: int = 0

## How many ticks of pose history to keep. Clamped up to [member delay_ticks] + 1.
##
## Bounded on purpose: a history that grows with the round is a memory leak with a
## plausible name, and this family has shipped one of those in a recorder already —
## dot-timer's [code]max_replay_seconds[/code] was a setting nothing read.
@export_range(2, 100000, 1) var history_ticks: int = 128


func env_prefix() -> String:
	return "DOT_SPECTATE_"


func cli_prefix() -> String:
	return "--spectate-"


func validate() -> DotResult:
	if delay_ticks > 0 and history_ticks <= delay_ticks:
		return DotResult.fail(
			DotError.CODE_INVALID,
			(
				"A delay of %d ticks needs more than %d ticks of history, or the "
				+ "camera asks for a tick that has already been thrown away and "
				+ "silently shows the oldest one it still has."
			) % [delay_ticks, history_ticks]
		)

	return DotResult.success(null)


## Whether a viewer may actually roam: asked for, and not contradicted by a restricted
## camera.
##
## Not a validation error: roaming defaults on, so a game that sets [code]force_camera 1[/code]
## and nothing else has said everything it meant, and failing its setup over the default
## would turn off spectating altogether. The restriction wins, silently by design.
func roaming_permitted() -> bool:
	return allow_roaming and force_camera == 0


## Whether the policy forces first person regardless of what a viewer asked for.
func forces_first_person() -> bool:
	return force_camera == 1


func forbids_everything() -> bool:
	return force_camera == 2


# --- Server cvars ------------------------------------------------------------

const CVAR_FORCE_CAMERA := "mp_forcecamera"
const CVAR_ROAM := "mp_freeroam"
const CVAR_ROAM_SPEED := "mp_freeroam_speed"

func cvar_specs() -> Array[Dictionary]:
	return [
		{"name": CVAR_FORCE_CAMERA, "value": str(force_camera), "min": 0.0, "max": 2.0,
			"description": "Who a spectator may watch: 0 anybody, 1 own team only (first person, no free roam), 2 nobody"},
		{"name": CVAR_ROAM, "value": "1" if allow_roaming else "0", "min": 0.0, "max": 1.0,
			"description": "1 lets spectators fly a free camera (needs mp_forcecamera 0), 0 keeps them on players"},
		{"name": CVAR_ROAM_SPEED, "value": str(roam_speed), "min": 0.5, "max": 200.0,
			"description": "Free camera speed in metres a second"},
	]


## Registers the spectator cvars through [param add], a server module's [code]add_cvar[/code]
## or anything shaped [code](name, default, description, flags) -> cvar[/code] with a
## [code]changed[/code] signal and [code]get_string()[/code], and keeps these rules in step.
## Pass dot-server's FLAG_REPLICATED so clients' mirrors follow. Duck-typed because
## dot-server is not a dependency; a value the cvar already holds (argv, a config file) is
## read back after registering.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for spec in cvar_specs():
		var cvar_name: String = spec["name"]
		var made_cvar: Variant = add.call(cvar_name, String(spec["value"]), String(spec["description"]), flags)
		if not (made_cvar is Object) or made_cvar == null:
			continue
		var cv := made_cvar as Object
		if cv.has_method(&"with_range"):
			cv.call(&"with_range", float(spec["min"]), float(spec["max"]))
		if cv.has_signal(&"changed"):
			cv.connect(&"changed", _on_cvar_changed.bind(cvar_name))
		if cv.has_method(&"get_string"):
			var _applied := set_cvar(cvar_name, String(cv.call(&"get_string")))
		made.append(cv)
	return made


## Follows a server's values through [param source] (dot-server's [code]DotClientLink[/code],
## or anything with [code]replicated_cvar(name, fallback)[/code] and a
## [code]replicated_cvar_changed(name, value)[/code] signal). False when it cannot.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	for spec in cvar_specs():
		var held := String(source.call(&"replicated_cvar", spec["name"], ""))
		if held != "":
			var _applied := set_cvar(spec["name"], held)
	if not source.is_connected(&"replicated_cvar_changed", _on_replicated_cvar):
		source.connect(&"replicated_cvar_changed", _on_replicated_cvar)
	return true


## Applies one cvar by name. False for another name or a value that does not parse.
func set_cvar(cvar_name: String, value: String) -> bool:
	var text := value.strip_edges()
	match cvar_name:
		CVAR_FORCE_CAMERA:
			if not text.is_valid_int() or text.to_int() < 0 or text.to_int() > 2:
				return false
			force_camera = text.to_int()
		CVAR_ROAM:
			if text.to_lower() in ["1", "true", "on"]:
				allow_roaming = true
			elif text.to_lower() in ["0", "false", "off"]:
				allow_roaming = false
			else:
				return false
		CVAR_ROAM_SPEED:
			if not text.is_valid_float():
				return false
			roam_speed = clampf(text.to_float(), 0.5, 200.0)
		_:
			return false
	rules_changed.emit()
	return true


func _on_cvar_changed(_old: Variant, new_value: Variant, cvar_name: String) -> void:
	var _applied := set_cvar(cvar_name, str(new_value))


func _on_replicated_cvar(cvar_name: String, value: String) -> void:
	var _applied := set_cvar(cvar_name, value)
