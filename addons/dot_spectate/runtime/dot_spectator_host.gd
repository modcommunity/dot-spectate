class_name DotSpectatorHost
extends Node

## The wrapper every game wrote around [DotSpectatorManager]: build it, bind the four game
## questions, forward the viewer calls, and keep the pieces a game would otherwise copy.
##
## [codeblock]
## class_name MyGameSpectate
## extends DotSpectatorHost
##
## func _participants() -> PackedStringArray: return game.player_keys()
## func _team_of(key: String) -> int: return game.team_of(key)
## func _is_alive(key: String) -> bool: return game.is_alive(key)
## func _pose_of(key: String) -> Transform3D:
##     return eye_pose(game.position_of(key), game.pitch_of(key), game.yaw_of(key))
## func _current_tick() -> int: return game.current_tick()
##
## # then add_child(spectate); spectate.setup(); spectate.advance_live() once a tick.
## [/codeblock]
##
## Keys are [String] like the manager's. A game keyed by [int] or [StringName] converts in
## its subclass. Everything a game differs in is an export or a [code]_hook[/code]; a game
## that needs more overrides the method and calls [code]super[/code].

## A viewer's view changed, by a call here, a retarget or a timer.
signal view_changed(key: String)

## Seconds the death cam holds. Converted with [member tick_rate].
@export var death_cam_seconds: float = 1.0
## Seconds the freeze cam holds on the killer. 0 skips it.
@export var freeze_cam_seconds: float = 1.5
@export var chase_distance: float = 3.5
@export var chase_height: float = 0.9
## How long the history ring is. Raise it with [code]rules.delay_ticks[/code].
@export var history_seconds: float = 4.0
## Ticks per second of the game's simulation.
@export var tick_rate: int = 64
## Metres from a body's origin to its eyes, for [method eye_pose].
@export var eye_height: float = 1.6
## Whether a client runs the chain itself. A mirror is told by the server instead.
@export var authoritative: bool = true
## An automatic choice of target goes to a team-mate when there is one.
@export var prefer_own_side: bool = false
## Key name shown in [method line_for]; the game binds the key.
@export var roam_key: String = "G"
## The game's own rules object, so cvars it bound are the rules in use. Null: a new one.
@export var rules: DotSpectatorRules = null

## [code](key: String) -> String[/code]: a name for the HUD line. Default: the key.
var name_fn: Callable = Callable()
## [code](key: String) -> int[/code]: which fixed camera a viewer in FIXED mode gets.
var fixed_index_fn: Callable = Callable()

var manager: DotSpectatorManager = null

var _stepping: bool = false
var _preferring: bool = false
var _seen_dead: Dictionary = {}


## Builds the manager. Call once, after the game's roster exists.
func setup() -> DotResult:
	manager = DotSpectatorManager.new()
	manager.name = "SpectatorManager"
	manager.authoritative = authoritative
	manager.rules = tune_rules(rules if rules != null else DotSpectatorRules.new())
	manager.participants_fn = _participants
	manager.team_fn = _team_of
	manager.alive_fn = _is_alive
	manager.pose_fn = _pose_of
	add_child(manager)

	var res := manager.setup()
	if not res.ok:
		manager.queue_free()
		manager = null
		return res.wrap("spectator host")

	manager.view_changed.connect(_on_view_changed)
	manager.retargeted.connect(_on_retargeted)
	DotLog.debug(_channel(), "spectating is set up", {
		"authoritative": authoritative,
		"force_camera": manager.rules.force_camera,
		"roaming": manager.rules.roaming_permitted(),
	})
	return DotResult.success(null)


# --- Hooks a game overrides --------------------------------------------------

## Everybody who could be watched.
func _participants() -> PackedStringArray:
	return PackedStringArray()


## Zero is no team.
func _team_of(_key: String) -> int:
	return 0


func _is_alive(_key: String) -> bool:
	return true


## Where somebody's eyes are, from where this process draws them. See [method eye_pose].
func _pose_of(_key: String) -> Transform3D:
	return Transform3D.IDENTITY


## The simulation's tick, for [method advance_live] and [method death].
func _current_tick() -> int:
	return 0


## The game's rule defaults beyond the exports, on [param r] (which is returned). The
## operator's [code]force_camera[/code] and [code]allow_roaming[/code] are not set here.
func _tune_rules(r: DotSpectatorRules) -> DotSpectatorRules:
	return r


## The DotLog channel. Override to log under the game's own.
func _channel() -> String:
	return "spectate.host"


## Applies the exports and then the game's hook to [param r].
func tune_rules(r: DotSpectatorRules) -> DotSpectatorRules:
	var rate := float(maxi(tick_rate, 1))
	r.death_cam_ticks = int(death_cam_seconds * rate)
	r.freeze_cam_ticks = int(freeze_cam_seconds * rate)
	r.chase_distance = chase_distance
	r.chase_height = chase_height
	r.history_ticks = maxi(int(history_seconds * rate), 2)
	return _tune_rules(r)


## A transform from a body's position and its pitch and yaw in degrees, eyes above it.
func eye_pose(position: Vector3, pitch_deg: float, yaw_deg: float) -> Transform3D:
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))
	return Transform3D(basis, position + Vector3(0.0, eye_height, 0.0))


# --- Ticks and events --------------------------------------------------------

func advance(tick: int) -> void:
	if manager != null:
		manager.advance(tick)


## [method advance] at [method _current_tick], for a game that ticks here.
func advance_live() -> void:
	advance(_current_tick())


## A client's tick when nothing emits respawns: a viewer seen dead and then alive is
## playing again. "Seen dead" rather than "alive", because a kill can arrive before the
## snapshot that says so.
func advance_client(tick: int) -> void:
	if manager == null:
		return
	manager.advance(tick)
	for key in manager.viewers():
		if not _participants().has(key):
			manager.stop(key)
			_seen_dead.erase(key)
		elif not _is_alive(key):
			_seen_dead[key] = true
		elif _seen_dead.has(key):
			_seen_dead.erase(key)
			manager.on_spawn(key)


## Somebody died: starts the death cam chain. [param tick] -1 is [method _current_tick].
func death(key: String, at: Vector3, by: String = "", tick: int = -1) -> void:
	if manager != null:
		manager.on_death(key, at, by, tick if tick >= 0 else _current_tick())


func spawned(key: String) -> void:
	if manager != null:
		manager.on_spawn(key)
		_seen_dead.erase(key)


## Call after the roster dropped the player.
func left(key: String) -> void:
	if manager != null:
		manager.on_leave(key)
		_seen_dead.erase(key)


# --- Viewer calls ------------------------------------------------------------

func _unset() -> DotResult:
	return DotResult.fail(DotError.CODE_STATE, "Spectating is not set up.")


func watch(key: String, target: String) -> DotResult:
	return manager.watch(key, target) if manager != null else _unset()


func stop(key: String) -> void:
	if manager != null:
		manager.stop(key)


func is_spectating(key: String) -> bool:
	return manager != null and manager.is_spectating(key)


func mode_of(key: String) -> int:
	return int(manager.view(key).mode) if manager != null else 0


## Who a viewer is watching, or "".
func watching(key: String) -> String:
	if not is_spectating(key):
		return ""
	return manager.view(key).target


## Where the viewer's camera goes this frame. Identity when they are playing.
func camera_for(key: String) -> Transform3D:
	if not is_spectating(key):
		return Transform3D.IDENTITY
	var view := manager.view(key)
	if view.mode == DotSpectatorView.Mode.FIXED and fixed_index_fn.is_valid():
		view.fixed_index = int(fixed_index_fn.call(key))
	return manager.camera_of(key)


func next_target(key: String) -> DotResult:
	return manager.next_target(key) if manager != null else _unset()


func previous_target(key: String) -> DotResult:
	return manager.previous_target(key) if manager != null else _unset()


## Next or previous target (direction 1 or -1), or the other camera (0), asked of the
## authority. A mirror is told, not asked.
func step(key: String, direction: int) -> DotResult:
	if manager == null:
		return _unset()
	if not authoritative:
		return DotResult.fail(DotError.CODE_STATE, "A mirror is told, not asked.")
	if not manager.is_spectating(key):
		return DotResult.fail(DotError.CODE_STATE, "You are playing, not watching.")
	if direction == 0:
		return cycle_mode(key)
	_stepping = true
	var moved := manager.next_target(key) if direction > 0 else manager.previous_target(key)
	_stepping = false
	return moved


## First person, chase, then roaming when the policy allows it; a refusal says why.
func cycle_mode(key: String) -> DotResult:
	if manager == null:
		return _unset()
	var view := manager.view(key)
	if not view.follows_target() or view.mode == DotSpectatorView.Mode.FREEZE_CAM:
		return DotResult.fail(DotError.CODE_STATE, "There is nobody in front of this camera.")
	var wanted := DotSpectatorView.Mode.CHASE
	if view.mode == DotSpectatorView.Mode.CHASE:
		wanted = DotSpectatorView.Mode.FIRST_PERSON
	var res := manager.set_mode(key, wanted)
	if res.ok and int(res.value) != wanted:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "This server only lets you watch through their eyes."
		)
	return res


## The free-roam key. Refused with a line to show when roaming is off.
func toggle_roam(key: String) -> DotResult:
	if manager == null:
		return _unset()
	if not manager.can_roam(key):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Free roam is off on this server.")
	return manager.toggle_roam(key)


func can_roam(key: String) -> bool:
	return manager != null and manager.can_roam(key)


func is_roaming(key: String) -> bool:
	return is_spectating(key) and manager.view(key).mode == DotSpectatorView.Mode.ROAMING


## Operator change of [code]force_camera[/code] (0 to 2), from the next decision on.
func set_force_camera(force_camera: int) -> void:
	if manager == null or manager.rules == null:
		return
	manager.rules.force_camera = clampi(force_camera, 0, 2)
	DotLog.info(_channel(), "the spectator policy changed", {
		"force_camera": manager.rules.force_camera,
	})


## The map's fixed cameras, for FIXED mode and the nobody-left-to-watch fallback.
func set_overviews(cameras: Array[Transform3D]) -> void:
	if manager != null:
		manager.fixed_cameras = cameras


## Client half: adopts a view the server decided, with its death position.
func apply_view(
	key: String, mode: int, target: String, killer: String, death_at: Vector3
) -> void:
	if manager == null:
		return
	var view := manager.view(key)
	view.mode = clampi(mode, 0, DotSpectatorView.Mode.size() - 1) as DotSpectatorView.Mode
	view.target = target
	view.killer = killer
	view.death_position = death_at
	view.until_tick = -1
	view_changed.emit(key)


## One HUD line, or "" while playing. Override for a game's own wording.
func line_for(key: String) -> String:
	if not is_spectating(key):
		return ""
	var view := manager.view(key)
	var who := _name_of(view.target)
	var roam := "   %s: free camera" % roam_key if can_roam(key) else ""
	match view.mode:
		DotSpectatorView.Mode.DEATH_CAM:
			return "you are out"
		DotSpectatorView.Mode.FREEZE_CAM:
			return "shot by %s" % who
		DotSpectatorView.Mode.FIXED:
			return "nobody left to watch%s" % roam
		DotSpectatorView.Mode.ROAMING:
			return "free camera   %s back to players" % roam_key
		DotSpectatorView.Mode.CHASE:
			return "watching %s  (behind)   click: next   F5: their eyes%s" % [who, roam]
		_:
			return "watching %s   click: next   F5: behind them%s" % [who, roam]


func _name_of(key: String) -> String:
	if name_fn.is_valid():
		return String(name_fn.call(key))
	return key


# --- Own side ----------------------------------------------------------------

func _on_view_changed(key: String, mode: int, target: String) -> void:
	_prefer_side(key, mode, target)
	view_changed.emit(key)


func _on_retargeted(key: String, _from: String, to: String, _reason: StringName) -> void:
	_prefer_side(key, int(manager.view(key).mode), to)
	view_changed.emit(key)


## The manager takes the first allowed name in key order, a stranger; somebody who just fell
## wants their own side. Only an automatic choice moves, never a viewer stepping.
func _prefer_side(key: String, mode: int, target: String) -> void:
	if not prefer_own_side or not authoritative or _stepping or _preferring or target == "":
		return
	if mode != DotSpectatorView.Mode.FIRST_PERSON and mode != DotSpectatorView.Mode.CHASE:
		return
	var mine := _team_of(key)
	if mine <= 0 or _team_of(target) == mine:
		return
	for candidate in manager.targets_for(key):
		if _team_of(candidate) != mine:
			continue
		_preferring = true
		var _moved := manager.watch(key, candidate, mode)
		_preferring = false
		return


func describe() -> Dictionary:
	return manager.describe() if manager != null else {}


func describe_lines() -> PackedStringArray:
	if manager == null:
		return PackedStringArray(["spectate: not set up"])
	return manager.describe_lines()
